import AppKit
import Observation
import SwiftUI

/// Wispr-style floating pill at the bottom of the screen: waveform while
/// recording, live transcript preview, spinner while finishing, errors.
/// Non-activating — it never steals focus from the app being dictated into.
/// All members must be called on the main thread.
final class OverlayPill {
    private let model = PillModel()
    private var panel: NSPanel?
    private var hideTimer: Timer?

    func showRecording() {
        hideTimer?.invalidate()
        model.text = ""
        model.message = ""
        model.bands = [Float](repeating: 0, count: SpectrumAnalyzer.bandCount)
        model.peaks = model.bands
        model.locked = false
        model.phase = .recording
        show()
    }

    func update(locked: Bool) {
        model.locked = locked
    }

    /// Rise instantly, fall gradually; peak caps fall slower — the classic
    /// analyzer feel, smoothed here because pushes arrive at ~12 fps.
    func update(spectrum: [Float]) {
        guard model.bands.count == spectrum.count else {
            model.bands = spectrum
            model.peaks = spectrum
            return
        }
        var bands = model.bands
        var peaks = model.peaks
        for i in 0..<spectrum.count {
            bands[i] = max(spectrum[i], bands[i] - 0.12)
            peaks[i] = max(bands[i], peaks[i] - 0.035)
        }
        model.bands = bands
        model.peaks = peaks
    }

    func showProcessing() {
        model.phase = .processing
    }

    func showError(_ message: String, hideAfter seconds: TimeInterval = 3) {
        model.message = message
        model.phase = .error
        show()
        hideTimer?.invalidate()
        hideTimer = Timer.scheduledTimer(withTimeInterval: seconds, repeats: false) { [weak self] _ in
            self?.hide()
        }
    }

    func update(text: String) {
        model.text = text
    }

    func hide() {
        hideTimer?.invalidate()
        hideTimer = nil
        model.phase = .hidden
        panel?.orderOut(nil)
    }

    private func show() {
        let panel = self.panel ?? makePanel()
        self.panel = panel
        if let screen = NSScreen.main {
            let frame = screen.visibleFrame
            panel.setFrameOrigin(NSPoint(
                x: frame.midX - panel.frame.width / 2,
                y: frame.minY + 24
            ))
        }
        panel.orderFrontRegardless()
    }

    private func makePanel() -> NSPanel {
        let panel = NSPanel(
            contentRect: NSRect(x: 0, y: 0, width: 460, height: 52),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.level = .statusBar
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = false
        panel.ignoresMouseEvents = true
        panel.hidesOnDeactivate = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .transient]
        panel.contentView = NSHostingView(rootView: PillView(model: model))
        return panel
    }
}

@Observable
final class PillModel {
    enum Phase { case hidden, recording, processing, error }
    var phase: Phase = .hidden
    var bands: [Float] = []
    var peaks: [Float] = []
    var text: String = ""
    var message: String = ""
    var locked = false
}

struct PillView: View {
    let model: PillModel

    var body: some View {
        VStack {
            Spacer(minLength: 0)
            content
                .padding(.horizontal, 16)
                .padding(.vertical, 9)
                .background(.ultraThinMaterial, in: Capsule())
                .overlay(Capsule().strokeBorder(.white.opacity(0.15)))
                .shadow(color: .black.opacity(0.35), radius: 10, y: 3)
        }
        .frame(maxWidth: .infinity)
        .padding(.bottom, 2)
    }

    @ViewBuilder
    private var content: some View {
        switch model.phase {
        case .hidden:
            EmptyView()
        case .recording:
            HStack(spacing: 10) {
                Image(systemName: model.locked ? "lock.fill" : "mic.fill")
                    .foregroundStyle(.red)
                WinampSpectrum(bands: model.bands, peaks: model.peaks)
            }
        case .processing:
            HStack(spacing: 10) {
                ProgressView()
                    .controlSize(.small)
                Text(model.text.isEmpty ? "Transcribing…" : model.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: 320, alignment: .leading)
            }
        case .error:
            HStack(spacing: 10) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(.orange)
                Text(model.message)
                    .lineLimit(2)
                    .frame(maxWidth: 360, alignment: .leading)
            }
        }
    }
}

/// Classic WinAmp-style spectrum: segmented cells per band, green base to
/// red tips, dim unlit cells, and bright falling peak caps on black.
private struct WinampSpectrum: View {
    var bands: [Float]
    var peaks: [Float]

    private let rows = 10

    var body: some View {
        Canvas { context, size in
            let count = bands.count
            guard count > 0, peaks.count == count else { return }
            let columnWidth = size.width / CGFloat(count)
            let rowHeight = size.height / CGFloat(rows)
            let cellWidth = columnWidth * 0.72
            let cellHeight = rowHeight * 0.68

            func cellRect(band: Int, row: Int) -> CGRect {
                CGRect(
                    x: CGFloat(band) * columnWidth + (columnWidth - cellWidth) / 2,
                    y: size.height - CGFloat(row + 1) * rowHeight + (rowHeight - cellHeight) / 2,
                    width: cellWidth,
                    height: cellHeight
                )
            }

            for band in 0..<count {
                let lit = Int((CGFloat(bands[band]) * CGFloat(rows)).rounded())
                for row in 0..<rows {
                    let color: Color
                    if row < lit {
                        if row >= rows - 2 {
                            color = Color(red: 1.0, green: 0.25, blue: 0.2)
                        } else if row >= rows - 4 {
                            color = Color(red: 1.0, green: 0.84, blue: 0.16)
                        } else {
                            color = Color(red: 0.2, green: 0.9, blue: 0.32)
                        }
                    } else {
                        color = Color.white.opacity(0.07)
                    }
                    context.fill(Path(cellRect(band: band, row: row)), with: .color(color))
                }
                if peaks[band] > 0.03 {
                    let peakRow = min(rows - 1, Int(CGFloat(peaks[band]) * CGFloat(rows)))
                    var rect = cellRect(band: band, row: peakRow)
                    rect.size.height *= 0.5
                    context.fill(Path(rect), with: .color(Color(red: 0.96, green: 0.96, blue: 0.9)))
                }
            }
        }
        .frame(width: 176, height: 28)
        .padding(.horizontal, 7)
        .padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color.black.opacity(0.88)))
        .animation(.linear(duration: 0.08), value: bands)
    }
}
