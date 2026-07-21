import AVFoundation

/// Captures microphone audio. Live buffers stream out (ordered) for the
/// streaming transcriber, while a 16 kHz mono copy accumulates as the batch
/// fallback. Also reports an RMS level for the overlay's meter.
final class AudioEngine {
    static let sampleRate: Double = 16000

    var onLevel: ((Float) -> Void)?

    private let engine = AVAudioEngine()
    private var samples: [Float] = []
    private let queue = DispatchQueue(label: "dictator.audio.capture")
    private var converter: AVAudioConverter?
    private var bufferContinuation: AsyncStream<AVAudioPCMBuffer>.Continuation?

    func requestPermission(_ completion: @escaping (Bool) -> Void) {
        switch AVCaptureDevice.authorizationStatus(for: .audio) {
        case .authorized:
            completion(true)
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .audio, completionHandler: completion)
        default:
            completion(false)
        }
    }

    /// Starts capture; the returned stream yields raw hardware-format buffers
    /// in arrival order and finishes when `stop()` is called.
    func start() throws -> AsyncStream<AVAudioPCMBuffer> {
        queue.sync { samples.removeAll() }
        let (bufferStream, continuation) = AsyncStream.makeStream(of: AVAudioPCMBuffer.self)
        bufferContinuation = continuation

        let input = engine.inputNode
        input.removeTap(onBus: 0)

        let inputFormat = input.outputFormat(forBus: 0)
        guard let targetFormat = AVAudioFormat(
            commonFormat: .pcmFormatFloat32,
            sampleRate: Self.sampleRate,
            channels: 1,
            interleaved: false
        ), let converter = AVAudioConverter(from: inputFormat, to: targetFormat) else {
            throw NSError(
                domain: "Dictator", code: 1,
                userInfo: [NSLocalizedDescriptionKey: "Could not configure audio conversion"]
            )
        }
        self.converter = converter

        input.installTap(onBus: 0, bufferSize: 4096, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }
            self.bufferContinuation?.yield(buffer)
            self.reportLevel(of: buffer)
            self.accumulate(buffer, converter: converter, targetFormat: targetFormat)
        }

        engine.prepare()
        try engine.start()
        return bufferStream
    }

    func stop() -> [Float] {
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        bufferContinuation?.finish()
        bufferContinuation = nil
        converter = nil
        return queue.sync { samples }
    }

    /// Drops leading/trailing silence (with a little padding) so the batch
    /// path doesn't waste decode time on dead air.
    static func trimSilence(_ samples: [Float], threshold: Float = 0.006) -> [Float] {
        guard
            let first = samples.firstIndex(where: { abs($0) > threshold }),
            let last = samples.lastIndex(where: { abs($0) > threshold })
        else { return [] }
        let pad = Int(sampleRate * 0.15)
        let start = max(0, first - pad)
        let end = min(samples.count, last + 1 + pad)
        return Array(samples[start..<end])
    }

    private func reportLevel(of buffer: AVAudioPCMBuffer) {
        guard let onLevel, let channel = buffer.floatChannelData?[0] else { return }
        let count = Int(buffer.frameLength)
        guard count > 0 else { return }
        var sum: Float = 0
        for i in stride(from: 0, to: count, by: 8) {
            let sample = channel[i]
            sum += sample * sample
        }
        let rms = (sum / Float(count / 8 + 1)).squareRoot()
        DispatchQueue.main.async { onLevel(rms) }
    }

    private func accumulate(
        _ buffer: AVAudioPCMBuffer,
        converter: AVAudioConverter,
        targetFormat: AVAudioFormat
    ) {
        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 16
        guard let out = AVAudioPCMBuffer(pcmFormat: targetFormat, frameCapacity: capacity) else { return }
        var conversionError: NSError?
        var consumed = false
        converter.convert(to: out, error: &conversionError) { _, outStatus in
            if consumed {
                outStatus.pointee = .noDataNow
                return nil
            }
            consumed = true
            outStatus.pointee = .haveData
            return buffer
        }
        guard conversionError == nil, let channel = out.floatChannelData?[0] else { return }
        let chunk = Array(UnsafeBufferPointer(start: channel, count: Int(out.frameLength)))
        queue.async { self.samples.append(contentsOf: chunk) }
    }
}
