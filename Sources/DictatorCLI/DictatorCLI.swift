import AVFoundation
import DictatorLLM
import FluidAudio

/// Offline smoke tests for the two model stacks:
///   DictatorCLI <audio-file>      — transcribe through Parakeet
///   DictatorCLI polish "<text>"   — polish through the embedded llama.cpp
/// Exercises the same paths the app uses, without speaking into the mic.
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
            let models = try await AsrModels.downloadAndLoad(version: .v3)
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
        guard !text.isEmpty else {
            FileHandle.standardError.write(Data("usage: DictatorCLI polish \"<text>\"\n".utf8))
            exit(64)
        }
        guard let modelURL = LlamaEngine.sideloadedModelURL() else {
            FileHandle.standardError.write(
                Data("no .gguf found in \(LlamaEngine.modelsDirectory.path)\n".utf8))
            exit(1)
        }
        do {
            var start = Date()
            let engine = try LlamaEngine(modelURL: modelURL)
            print(String(format: "model load (%@): %.2fs", engine.modelName, Date().timeIntervalSince(start)))

            start = Date()
            let context = DictationContext(appName: "Slack", precedingText: "")
            let result = try engine.chat(
                system: PolishPrompt.system,
                user: PolishPrompt.user(text: text, context: context, tone: "casual")
            )
            print(String(format: "polish: %.2fs", Date().timeIntervalSince(start)))
            print(result)
        } catch {
            FileHandle.standardError.write(Data("error: \(error)\n".utf8))
            exit(1)
        }
    }
}
