import Foundation

protocol Transcriber: Sendable {
    var name: String { get }
    func transcribe(samples: [Float], sampleRate: Double) async throws -> String
}

/// M0 placeholder that proves the capture → process → inject loop end to end.
/// M1 replaces this with Parakeet (FluidAudio) and a whisper.cpp fallback.
struct StubTranscriber: Transcriber {
    let name = "stub"

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        let seconds = Double(samples.count) / sampleRate
        let peak = samples.map(abs).max() ?? 0
        return String(
            format: "[Dictator M0: heard %.1fs of audio, peak level %.2f — real transcription arrives in M1]",
            seconds, peak
        )
    }
}
