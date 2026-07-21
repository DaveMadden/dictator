import AVFoundation
import FluidAudio

/// Offline smoke test for the ASR stack: `swift run DictatorCLI <audio-file>`.
/// Exercises the same model load + transcribe path the app uses, without
/// needing to speak into the mic.
@main
struct DictatorCLI {
    static func main() async {
        let args = CommandLine.arguments
        guard args.count == 2 else {
            FileHandle.standardError.write(Data("usage: DictatorCLI <audio-file>\n".utf8))
            exit(64)
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
}
