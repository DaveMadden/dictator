import AVFoundation
import FluidAudio
import Foundation

/// Local ASR via NVIDIA Parakeet TDT 0.6B v3 (CoreML, through FluidAudio).
/// Models are fetched once into FluidAudio's cache on first load and stay
/// resident in memory afterwards — cold load is the biggest latency cost.
///
/// Two paths share the same loaded models:
/// - streaming: per-dictation StreamingAsrManager fed live audio buffers,
///   emitting volatile/confirmed updates while the user is still speaking
/// - batch: one-shot transcribe of a full sample buffer, used as fallback
actor ParakeetTranscriber: Transcriber {
    let name = "parakeet-tdt-0.6b-v3"

    /// Sideloaded models (scripts/models.sh install) are preferred over the
    /// runtime download so an air-gapped machine never touches the network.
    static let localModelsDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Dictator/models/parakeet-tdt-0.6b-v3-coreml", isDirectory: true)

    private var loaded: (models: AsrModels, manager: AsrManager)?
    private var loadTask: Task<(AsrModels, AsrManager), Error>?
    private var stream: StreamingAsrManager?

    func warmUp() async throws {
        _ = try await loadedPair()
    }

    // MARK: Batch

    func transcribe(samples: [Float], sampleRate: Double) async throws -> String {
        guard samples.count >= Int(sampleRate * 0.3) else { return "" }
        let (_, manager) = try await loadedPair()
        let result = try await manager.transcribe(samples, source: .microphone)
        return result.text
    }

    // MARK: Streaming

    func startStream() async throws -> AsyncStream<StreamingTranscriptionUpdate> {
        if let stale = stream {
            await stale.cancel()
            stream = nil
        }
        let (models, _) = try await loadedPair()
        let session = StreamingAsrManager(config: .streaming)
        try await session.start(models: models, source: .microphone)
        stream = session
        return await session.transcriptionUpdates
    }

    func feed(_ buffer: AVAudioPCMBuffer) async {
        await stream?.streamAudio(buffer)
    }

    func finishStream() async throws -> String {
        guard let session = stream else { return "" }
        stream = nil
        return try await session.finish()
    }

    func cancelStream() async {
        if let session = stream {
            await session.cancel()
        }
        stream = nil
    }

    // MARK: Model loading

    private func loadedPair() async throws -> (AsrModels, AsrManager) {
        if let loaded { return loaded }
        if loadTask == nil {
            loadTask = Task {
                let models: AsrModels
                if AsrModels.modelsExist(at: Self.localModelsDirectory) {
                    NSLog("Dictator: loading sideloaded models (offline)")
                    models = try await AsrModels.load(from: Self.localModelsDirectory, version: .v3)
                } else {
                    NSLog("Dictator: no sideloaded models — downloading to cache (one-time)")
                    models = try await AsrModels.downloadAndLoad(version: .v3)
                }
                let manager = AsrManager(config: .default)
                try await manager.initialize(models: models)
                return (models, manager)
            }
        }
        do {
            let pair = try await loadTask!.value
            loaded = pair
            return pair
        } catch {
            loadTask = nil
            throw error
        }
    }
}
