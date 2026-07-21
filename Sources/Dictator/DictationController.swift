import AppKit
import AVFoundation
import FluidAudio
#if DICTATOR_LLM
import DictatorLLM
#endif

/// Orchestrates one dictation cycle: hotkey down starts capture and a
/// streaming transcription session that feeds the pill's live preview;
/// hotkey up batch-decodes the full recording (streaming text is only a
/// fallback), formats, polishes, and injects the result.
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
    private let injector = Injector()
    private let pill = OverlayPill()
    private var pressActive = false
    private var streamingActive = false
    private var forwardTask: Task<Void, Never>?
    private var recordingCapTimer: Timer?

    func showHandsFreeLock() {
        pill.update(locked: true)
    }

    func pasteFromHistory(_ text: String) {
        if !injector.paste(text) {
            report("A password field is focused — not pasting")
        }
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
            #if DICTATOR_LLM
            if SettingsStore.shared.llmEnabled,
               let modelURL = LlamaEngine.resolveModelURL(customPath: SettingsStore.shared.llmModelPath) {
                await LlamaPolisher.shared.warmUp(modelURL: modelURL)
            }
            #endif
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
                    self.audio.onSpectrum = { [weak self] bands in self?.pill.update(spectrum: bands) }
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
        audio.onSpectrum = nil
        let samples = audio.stop()
        state = .processing
        pill.showProcessing()
        Task { @MainActor in
            await forwardTask?.value
            // Streaming powers the live preview only. The sliding-window
            // stitcher garbles chunk seams on long takes (dropped spans,
            // "renewal" → "renewed.al"), so the final text always comes from
            // a full-context batch decode of the complete recording; the
            // stream's text is kept solely as a fallback.
            var streamText = ""
            if streamingActive {
                do {
                    streamText = try await transcriber.finishStream()
                } catch {
                    NSLog("Dictator: streaming finish failed: %@", "\(error)")
                }
            }
            var text = ""
            do {
                text = try await transcriber.transcribe(
                    samples: AudioEngine.trimSilence(samples),
                    sampleRate: AudioEngine.sampleRate
                )
            } catch {
                NSLog("Dictator: batch decode failed (%@), using streaming text", "\(error)")
            }
            if text.isEmpty { text = streamText }
            if text.isEmpty, streamText.isEmpty, samples.count > Int(AudioEngine.sampleRate) {
                report("Transcription produced no text")
                state = .idle
                return
            }
            var final = formatter.format(text)
            if !final.isEmpty {
                let context = ContextCapture.capture()
                // Record before the LLM pass: if polish ever crashes or hangs,
                // the dictation is already recoverable from History.
                HistoryStore.shared.add(raw: text, text: final, app: context.appName)
                final = await polishIfPossible(final, context: context)
                // The polish model sometimes emits markdown-style soft breaks
                // (trailing spaces before a newline); normalize them away.
                final = final.replacingOccurrences(
                    of: " +\\n", with: "\n", options: .regularExpression)
                HistoryStore.shared.updateLastText(final)
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
        #if DICTATOR_LLM
        let settings = SettingsStore.shared
        guard settings.llmEnabled else { return "AI polish: off" }
        if let url = LlamaEngine.resolveModelURL(customPath: settings.llmModelPath) {
            return "AI polish: embedded (\(url.lastPathComponent))"
        }
        if !settings.llmModelPath.trimmingCharacters(in: .whitespaces).isEmpty {
            return "AI polish: ⚠️ no model at configured path — check Settings"
        }
        return "AI polish: no model — set a model path in Settings"
        #else
        return "AI polish: not built in"
        #endif
    }

    /// Stage-2 polish for 8+ word dictations, through the embedded llama.cpp
    /// engine. Compiled in only with DICTATOR_LLM=1; always falls back to the
    /// deterministic text on any failure or guard rejection.
    private func polishIfPossible(_ text: String, context: DictationContext) async -> String {
        #if DICTATOR_LLM
        let settings = SettingsStore.shared
        guard settings.llmEnabled,
              text.split(separator: " ").count >= 8,
              let modelURL = LlamaEngine.resolveModelURL(customPath: settings.llmModelPath)
        else { return text }
        do {
            let raw = try await LlamaPolisher.shared.polish(
                text,
                appName: context.appName,
                precedingText: context.precedingText,
                tone: settings.tone(forApp: context.appName),
                modelURL: modelURL
            )
            let cleaned = PolishPrompt.stripWrapping(raw)
            guard PolishPrompt.plausibleRewrite(original: text, candidate: cleaned) else {
                NSLog("Dictator: LLM output failed plausibility guard, keeping deterministic text")
                return text
            }
            return cleaned
        } catch {
            NSLog("Dictator: LLM polish failed (%@), using deterministic text", "\(error)")
            return text
        }
        #else
        return text
        #endif
    }

    private func startStreaming(buffers: AsyncStream<AVAudioPCMBuffer>) {
        streamingActive = false
        forwardTask = Task { @MainActor in
            do {
                try await transcriber.startStream()
                self.streamingActive = true
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
