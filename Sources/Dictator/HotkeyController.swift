import AppKit
import CoreGraphics

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
        didSet { keyIsDown = false }
    }

    private static let spaceKeyCode: Int64 = 49

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapThread: Thread?
    private var tapRunLoop: CFRunLoop?
    private var keyIsDown = false
    private var swallowSpaceUp = false

    @discardableResult
    func start() -> Bool {
        stop()
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
                let swallow = controller.handle(type: type, event: event)
                return swallow ? nil : Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
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
        keyIsDown = false
        swallowSpaceUp = false
    }

    /// Returns true when the event should be swallowed (not delivered to apps).
    private func handle(type: CGEventType, event: CGEvent) -> Bool {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return false
        }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        switch type {
        case .flagsChanged:
            guard keyCode == hotkey.keyCode else { return false }
            let active = event.flags.contains(hotkey.flag)
            if active && !keyIsDown {
                keyIsDown = true
                DispatchQueue.main.async { self.onPress?() }
            } else if !active && keyIsDown {
                keyIsDown = false
                DispatchQueue.main.async { self.onRelease?() }
            }
            return false
        case .keyDown:
            guard keyIsDown, keyCode == Self.spaceKeyCode else { return false }
            swallowSpaceUp = true
            DispatchQueue.main.async { self.onLock?() }
            return true
        case .keyUp:
            guard swallowSpaceUp, keyCode == Self.spaceKeyCode else { return false }
            swallowSpaceUp = false
            return true
        default:
            return false
        }
    }
}
