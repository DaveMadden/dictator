import AVFoundation
import FluidAudio
#if DICTATOR_LLM
import DictatorLLM
#endif

/// Offline smoke tests for the model stacks, exercising the same paths the app
/// uses without speaking into the mic:
///   DictatorCLI <audio-file>      — transcribe through Parakeet
///   DictatorCLI polish "<text>"   — polish through llama.cpp (DICTATOR_LLM=1)
/// Like the app, this never downloads: models must already be installed.
@main
struct DictatorCLI {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count >= 2 else {
            FileHandle.standardError.write(
                Data("usage: DictatorCLI <audio-file> | DictatorCLI polish \"<text>\"\n".utf8))
            exit(64)
        }
        if args[1] == "polish" {
            await polish(text: args.count > 2 ? args[2] : "")
            return
        }
        do {
            let url = URL(fileURLWithPath: args[1])
            let file = try AVAudioFile(forReading: url)
            guard
                let buffer = AVAudioPCMBuffer(
                    pcmFormat: file.processingFormat,
                    frameCapacity: AVAudioFrameCount(file.length)
                )
            else {
                throw NSError(
                    domain: "DictatorCLI", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "could not allocate audio buffer"]
                )
            }
            try file.read(into: buffer)

            var start = Date()
            let sideloaded = FileManager.default
                .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
                .appendingPathComponent("Dictator/models/parakeet-tdt-0.6b-v3-coreml", isDirectory: true)
            let cache = AsrModels.defaultCacheDirectory()
            let modelsDir: URL
            if AsrModels.modelsExist(at: sideloaded) {
                modelsDir = sideloaded
            } else if AsrModels.modelsExist(at: cache) {
                modelsDir = cache
            } else {
                throw NSError(
                    domain: "DictatorCLI", code: 2,
                    userInfo: [NSLocalizedDescriptionKey:
                        "speech models not installed — run `make install-models-from-repo` (this tool never downloads)"]
                )
            }
            let models = try await AsrModels.load(from: modelsDir, version: .v3)
            let manager = AsrManager(config: .default)
            try await manager.initialize(models: models)
            print(String(format: "model load: %.2fs", Date().timeIntervalSince(start)))

            start = Date()
            let result = try await manager.transcribe(buffer, source: .system)
            print(String(
                format: "transcribe: %.2fs wall, %.2fs reported, confidence %.2f",
                Date().timeIntervalSince(start), result.processingTime, result.confidence
            ))
            print(result.text)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }

    static func polish(text: String) async {
        #if !DICTATOR_LLM
        FileHandle.standardError.write(
            Data("polish is not compiled into this build — rebuild with DICTATOR_LLM=1\n".utf8))
        exit(64)
        #else
        guard !text.isEmpty else {
            FileHandle.standardError.write(
                Data("usage: DictatorCLI polish \"<text>\" [model-file-or-folder]\n".utf8))
            exit(64)
        }
        let customPath = CommandLine.arguments.count > 3 ? CommandLine.arguments[3] : nil
        guard let modelURL = LlamaEngine.resolveModelURL(customPath: customPath) else {
            FileHandle.standardError.write(
                Data("no GGUF model found (looked in \(customPath ?? LlamaEngine.modelsDirectory.path))\n".utf8))
            exit(1)
        }
        do {
            var start = Date()
            let engine = try LlamaEngine(modelURL: modelURL)
            print(String(format: "model load (%@): %.2fs", engine.modelName, Date().timeIntervalSince(start)))

            start = Date()
            let result = try engine.chat(
                system: PolishPrompt.system,
                user: PolishPrompt.user(
                    text: text, appName: "Slack", precedingText: "", tone: "casual")
            )
            print(String(format: "polish: %.2fs", Date().timeIntervalSince(start)))
            print(result)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
        #endif
    }
}
