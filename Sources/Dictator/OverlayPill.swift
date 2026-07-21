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
        model.level = 0
        model.locked = false
        model.phase = .recording
        show()
    }

    func update(locked: Bool) {
        model.locked = locked
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

    func update(level: Float) {
        model.level = level
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
    var level: Float = 0
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
                LevelBars(level: model.level)
                Text(model.text.isEmpty ? "Listening…" : model.text)
                    .lineLimit(1)
                    .truncationMode(.head)
                    .foregroundStyle(model.text.isEmpty ? .secondary : .primary)
                    .frame(maxWidth: 320, alignment: .leading)
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

private struct LevelBars: View {
    var level: Float

    private static let profile: [CGFloat] = [0.5, 0.8, 1.0, 0.7, 0.55]

    var body: some View {
        HStack(spacing: 2.5) {
            ForEach(0..<Self.profile.count, id: \.self) { index in
                Capsule()
                    .fill(.red)
                    .frame(width: 3, height: height(index))
            }
        }
        .frame(height: 20)
        .animation(.easeOut(duration: 0.12), value: level)
    }

    private func height(_ index: Int) -> CGFloat {
        let boost = CGFloat(min(1, level * 14))
        return 4 + 15 * boost * Self.profile[index]
    }
}
