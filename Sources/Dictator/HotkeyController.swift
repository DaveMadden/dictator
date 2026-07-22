import AppKit
import CoreGraphics
import OSLog

/// Watches the configured push-to-talk key globally via a CGEventTap.
/// Requires the Accessibility permission; `start()` returns false until it
/// has been granted.
final class HotkeyController {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    /// Space pressed while the hotkey is physically held (hands-free lock).
    /// The space keystroke is swallowed so it never reaches the focused app.
    var onLock: (() -> Void)?
    var hotkey: Hotkey = .fn {
        didSet { state.hotkey = hotkey }
    }

    private let log = Logger(
        subsystem: Bundle.main.bundleIdentifier ?? "com.davidmadden.dictator",
        category: "hotkey"
    )
    private let state = HotkeyStateMachine()

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?

    @discardableResult
    func start() -> Bool {
        stop()
        state.hotkey = hotkey
        let mask = CGEventMask(
            (1 << CGEventType.flagsChanged.rawValue)
                | (1 << CGEventType.keyDown.rawValue)
                | (1 << CGEventType.keyUp.rawValue)
        )
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<HotkeyController>.fromOpaque(refcon).takeUnretainedValue()
                return controller.handleTap(type: type, event: event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            log.error("Dictator hotkey: failed to create event tap")
            return false
        }
        eventTap = tap
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CGEvent.tapEnable(tap: tap, enable: true)

        // The tap must NOT live on the main runloop: this is an active tap on
        // every keystroke, and macOS queues system-wide keyboard input behind
        // it — a hung main thread would freeze typing everywhere. A dedicated
        // thread keeps input flowing no matter what the app is doing.
        let thread = Thread { [weak self] in
            guard let self, let source = self.runLoopSource else { return }
            self.tapRunLoop = CFRunLoopGetCurrent()
            CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .commonModes)
            CFRunLoopRun()
        }
        thread.name = "dictator.eventtap"
        thread.qualityOfService = .userInteractive
        tapThread = thread
        thread.start()
        log.notice("Dictator hotkey: listener started for \(self.hotkey.title, privacy: .public)")
        return true
    }

    func stop() {
        if let runLoop = tapRunLoop {
            CFRunLoopStop(runLoop)
            tapRunLoop = nil
        }
        tapThread = nil
        if let source = runLoopSource {
            CFRunLoopSourceInvalidate(source)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        state.reset()
    }

    private func handleTap(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            log.notice(
                "Dictator hotkey: event tap disabled by \(self.tapDisableReason(for: type), privacy: .public); re-enabling"
            )
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let outcome: HotkeyEventOutcome
        switch type {
        case .flagsChanged, .tapDisabledByTimeout, .tapDisabledByUserInput:
            outcome = state.handleMonitorEvent(type: type, keyCode: keyCode, flags: event.flags)
        case .keyDown, .keyUp:
            outcome = state.handleGuardEvent(type: type, keyCode: keyCode)
        default:
            return Unmanaged.passUnretained(event)
        }

        apply(outcome)
        return outcome.swallowEvent ? nil : Unmanaged.passUnretained(event)
    }

    private func apply(_ outcome: HotkeyEventOutcome) {
        for action in outcome.tapActions {
            switch action {
            case .reenableMonitorTap, .reenableGuardTap:
                if let eventTap {
                    CGEvent.tapEnable(tap: eventTap, enable: true)
                }
            case .enableGuardTap, .disableGuardTap:
                break
            }
        }

        if outcome.emitPress {
            log.debug("Dictator hotkey: detected hotkey press")
            DispatchQueue.main.async { self.onPress?() }
        }
        if outcome.emitRelease {
            log.debug("Dictator hotkey: detected hotkey release")
            DispatchQueue.main.async { self.onRelease?() }
        }
        if outcome.emitLock {
            log.debug("Dictator hotkey: swallowed lock chord")
            DispatchQueue.main.async { self.onLock?() }
        }
    }

    private func tapDisableReason(for type: CGEventType) -> String {
        switch type {
        case .tapDisabledByTimeout:
            return "timeout"
        case .tapDisabledByUserInput:
            return "user input"
        default:
            return "unknown"
        }
    }
}
