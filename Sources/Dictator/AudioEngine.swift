import Accelerate
import AVFoundation

/// Captures microphone audio. Live buffers stream out (ordered) for the
/// streaming transcriber, while a 16 kHz mono copy accumulates as the batch
/// fallback. Also reports a frequency spectrum for the overlay's analyzer.
final class AudioEngine {
    static let sampleRate: Double = 16000

    var onSpectrum: (([Float]) -> Void)?
    private let analyzer = SpectrumAnalyzer()

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
        if let onSpectrum {
            analyzer.push(chunk)
            let bands = analyzer.bands()
            DispatchQueue.main.async { onSpectrum(bands) }
        }
    }
}

/// 512-point FFT over the most recent 16 kHz mono audio, folded into
/// log-spaced bands (60 Hz – 8 kHz) for the overlay's spectrum display.
/// Used only from the audio tap thread.
final class SpectrumAnalyzer {
    static let bandCount = 16

    /// Calibrated against a quiet room reading ~-30 dB (power) per band:
    /// silence stays dark, conversational speech spans the scale. The tilt
    /// lifts high bands so fricatives register despite their lower energy.
    private static let floorDB: Float = -18
    private static let rangeDB: Float = 30
    private static let highTiltDB: Float = 3

    private let fftSize = 512
    private let log2n = vDSP_Length(9)
    private let setup: FFTSetup
    private var window = [Float](repeating: 0, count: 512)
    private var ring = [Float](repeating: 0, count: 512)
    private var ringIndex = 0
    private let bandEdges: [Int]

    init() {
        setup = vDSP_create_fftsetup(log2n, FFTRadix(kFFTRadix2))!
        vDSP_hann_window(&window, vDSP_Length(fftSize), Int32(vDSP_HANN_NORM))
        let binHz = AudioEngine.sampleRate / Double(fftSize)
        var edges: [Int] = []
        for i in 0...Self.bandCount {
            let hz = 60.0 * pow(8000.0 / 60.0, Double(i) / Double(Self.bandCount))
            edges.append(min(fftSize / 2 - 1, max(1, Int(hz / binHz))))
        }
        bandEdges = edges
    }

    deinit {
        vDSP_destroy_fftsetup(setup)
    }

    func push(_ samples: [Float]) {
        for sample in samples {
            ring[ringIndex] = sample
            ringIndex = (ringIndex + 1) % fftSize
        }
    }

    func bands() -> [Float] {
        var frame = [Float](repeating: 0, count: fftSize)
        for i in 0..<fftSize {
            frame[i] = ring[(ringIndex + i) % fftSize]
        }
        vDSP_vmul(frame, 1, window, 1, &frame, 1, vDSP_Length(fftSize))

        var real = [Float](repeating: 0, count: fftSize / 2)
        var imag = [Float](repeating: 0, count: fftSize / 2)
        var magnitudes = [Float](repeating: 0, count: fftSize / 2)
        real.withUnsafeMutableBufferPointer { realPtr in
            imag.withUnsafeMutableBufferPointer { imagPtr in
                var split = DSPSplitComplex(realp: realPtr.baseAddress!, imagp: imagPtr.baseAddress!)
                frame.withUnsafeBufferPointer { framePtr in
                    framePtr.baseAddress!.withMemoryRebound(to: DSPComplex.self, capacity: fftSize / 2) {
                        vDSP_ctoz($0, 2, &split, 1, vDSP_Length(fftSize / 2))
                    }
                }
                vDSP_fft_zrip(setup, &split, 1, log2n, FFTDirection(FFT_FORWARD))
                vDSP_zvmags(&split, 1, &magnitudes, 1, vDSP_Length(fftSize / 2))
            }
        }

        var out = [Float](repeating: 0, count: Self.bandCount)
        for band in 0..<Self.bandCount {
            let lo = bandEdges[band]
            let hi = max(lo + 1, bandEdges[band + 1])
            var sum: Float = 0
            for bin in lo..<hi {
                sum += magnitudes[bin]
            }
            let tilt = Self.highTiltDB * Float(band) / Float(Self.bandCount - 1)
            let db = 10 * log10(sum / Float(hi - lo) + 1e-9) + tilt
            out[band] = min(1, max(0, (db - Self.floorDB) / Self.rangeDB))
        }
        return out
    }
}
