import AppKit
import AVFoundation
import DictatorLLM
import FluidAudio

/// Orchestrates one dictation cycle: hotkey down starts capture and a
/// streaming transcription session (live preview in the pill); hotkey up
/// finishes the stream and injects the formatted result. If streaming fails,
/// the accumulated 16 kHz buffer is batch-transcribed instead.
final class DictationController {
    enum State { case idle, recording, processing }

    /// Recordings are capped so a forgotten toggle-mode session can't run
    /// forever accumulating audio.
    static let maxRecordingSeconds: TimeInterval = 300

    private(set) var state: State = .idle {
        didSet { onStateChange?(state) }
    }
    var onStateChange: ((State) -> Void)?
    var onModelStatus: ((String) -> Void)?

    private let audio = AudioEngine()
    private let transcriber = ParakeetTranscriber()
    private let formatter = DeterministicFormatter()
    private let llm = LLMFormatter()
    private let injector = Injector()
    private let pill = OverlayPill()
    private var llmAvailable = false
    private var llmLastChecked = Date.distantPast
    private var pressActive = false
    private var streamingActive = false
    private var forwardTask: Task<Void, Never>?
    private var updatesTask: Task<Void, Never>?
    private var recordingCapTimer: Timer?

    func showHandsFreeLock() {
        pill.update(locked: true)
    }

    func warmUpModel() {
        onModelStatus?("Model: loading…")
        Task { @MainActor in
            do {
                try await transcriber.warmUp()
                onModelStatus?("Model: ready (Parakeet TDT v3)")
            } catch {
                onModelStatus?("Model: load failed — retries on next dictation")
                report("Model load failed: \(error.localizedDescription)")
            }
            if SettingsStore.shared.llmEnabled,
               let modelURL = LlamaEngine.resolveModelURL(customPath: SettingsStore.shared.llmModelPath) {
                await LlamaPolisher.shared.warmUp(modelURL: modelURL)
            }
        }
    }

    func beginDictation() {
        guard state == .idle else { return }
        pressActive = true
        audio.requestPermission { [weak self] granted in
            DispatchQueue.main.async {
                guard let self, self.pressActive, self.state == .idle else { return }
                guard granted else {
                    self.report("Microphone access needed: System Settings → Privacy & Security → Microphone")
                    return
                }
                do {
                    let buffers = try self.audio.start()
                    self.state = .recording
                    self.pill.showRecording()
                    self.audio.onLevel = { [weak self] level in self?.pill.update(level: level) }
                    self.startStreaming(buffers: buffers)
                    self.startRecordingCapTimer()
                } catch {
                    self.report("Could not start audio capture: \(error.localizedDescription)")
                }
            }
        }
    }

    func endDictation() {
        pressActive = false
        guard state == .recording else { return }
        recordingCapTimer?.invalidate()
        recordingCapTimer = nil
        audio.onLevel = nil
        let samples = audio.stop()
        state = .processing
        pill.showProcessing()
        Task { @MainActor in
            var text = ""
            await forwardTask?.value
            updatesTask?.cancel()
            if streamingActive {
                do {
                    text = try await transcriber.finishStream()
                } catch {
                    NSLog("Dictator: streaming finish failed, falling back to batch: %@", "\(error)")
                }
            }
            if text.isEmpty {
                let trimmed = AudioEngine.trimSilence(samples)
                do {
                    text = try await transcriber.transcribe(
                        samples: trimmed,
                        sampleRate: AudioEngine.sampleRate
                    )
                } catch {
                    report("Transcription failed: \(error.localizedDescription)")
                    state = .idle
                    return
                }
            }
            var final = formatter.format(text)
            if !final.isEmpty {
                let context = ContextCapture.capture()
                final = await polishIfPossible(final, context: context)
                HistoryStore.shared.add(raw: text, text: final, app: context.appName)
                if !injector.paste(final) {
                    report("A password field is focused — not pasting (text is in History)")
                    state = .idle
                    return
                }
            }
            pill.hide()
            state = .idle
        }
    }

    var polishStatus: String {
        let settings = SettingsStore.shared
        guard settings.llmEnabled else { return "AI polish: off" }
        if let url = LlamaEngine.resolveModelURL(customPath: settings.llmModelPath) {
            return "AI polish: embedded (\(url.lastPathComponent))"
        }
        if !settings.llmModelPath.trimmingCharacters(in: .whitespaces).isEmpty {
            return "AI polish: ⚠️ no model at configured path — check Settings"
        }
        if llmAvailable {
            return "AI polish: Ollama (\(settings.llmModel))"
        }
        return "AI polish: no engine — set a model path in Settings"
    }

    /// Stage-2 polish for 8+ word dictations. Backend priority: embedded
    /// llama.cpp (a .gguf sideloaded into App Support/Dictator/llm), then a
    /// running Ollama server. Always falls back to the deterministic text.
    private func polishIfPossible(_ text: String, context: DictationContext) async -> String {
        let settings = SettingsStore.shared
        guard settings.llmEnabled,
              text.split(separator: " ").count >= 8 else { return text }
        let tone = settings.tone(forApp: context.appName)

        if let modelURL = LlamaEngine.resolveModelURL(customPath: settings.llmModelPath) {
            do {
                let raw = try await LlamaPolisher.shared.polish(
                    text, context: context, tone: tone, modelURL: modelURL)
                let cleaned = LLMFormatter.stripWrapping(raw)
                guard LLMFormatter.plausibleRewrite(original: text, candidate: cleaned) else {
                    NSLog("Dictator: embedded LLM output failed plausibility guard")
                    return text
                }
                return cleaned
            } catch {
                NSLog("Dictator: embedded LLM polish failed (%@), using deterministic text", "\(error)")
                return text
            }
        }

        if Date().timeIntervalSince(llmLastChecked) > 120 {
            llmAvailable = await LLMFormatter.serverAvailable()
            llmLastChecked = Date()
        }
        guard llmAvailable else { return text }
        do {
            return try await llm.polish(
                text,
                model: settings.llmModel,
                context: context,
                tone: tone
            )
        } catch {
            llmAvailable = false
            NSLog("Dictator: LLM polish unavailable (%@), using deterministic text", "\(error)")
            return text
        }
    }

    private func startStreaming(buffers: AsyncStream<AVAudioPCMBuffer>) {
        streamingActive = false
        forwardTask = Task { @MainActor in
            do {
                let updates = try await transcriber.startStream()
                self.streamingActive = true
                self.updatesTask = Task { @MainActor in
                    var confirmed = ""
                    var volatile = ""
                    for await update in updates {
                        if update.isConfirmed {
                            confirmed += update.text
                            volatile = ""
                        } else {
                            volatile = update.text
                        }
                        self.pill.update(text: confirmed + volatile)
                    }
                }
                // Single sequential consumer keeps buffers in arrival order;
                // the stream buffers anything captured while the session spun up.
                for await buffer in buffers {
                    await self.transcriber.feed(buffer)
                }
            } catch {
                NSLog("Dictator: streaming unavailable, will batch-transcribe: %@", "\(error)")
                for await _ in buffers {}
            }
        }
    }

    private func startRecordingCapTimer() {
        recordingCapTimer?.invalidate()
        recordingCapTimer = Timer.scheduledTimer(
            withTimeInterval: Self.maxRecordingSeconds,
            repeats: false
        ) { [weak self] _ in
            self?.endDictation()
        }
    }

    private func report(_ message: String) {
        NSLog("Dictator: %@", message)
        pill.showError(message)
    }
}
