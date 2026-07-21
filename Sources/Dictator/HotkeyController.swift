import AppKit
import CoreGraphics

/// Watches the configured push-to-talk key globally via a CGEventTap.
/// Requires the Accessibility permission; `start()` returns false until it
/// has been granted.
final class HotkeyController {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    var hotkey: Hotkey = .fn {
        didSet { keyIsDown = false }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var keyIsDown = false

    @discardableResult
    func start() -> Bool {
        stop()
        let mask = CGEventMask(1 << CGEventType.flagsChanged.rawValue)
        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let controller = Unmanaged<HotkeyController>.fromOpaque(refcon).takeUnretainedValue()
                controller.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)
            },
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            return false
        }
        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
            runLoopSource = nil
        }
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
            eventTap = nil
        }
        keyIsDown = false
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap = eventTap { CGEvent.tapEnable(tap: tap, enable: true) }
            return
        }
        guard event.getIntegerValueField(.keyboardEventKeycode) == hotkey.keyCode else { return }
        let active = event.flags.contains(hotkey.flag)
        if active && !keyIsDown {
            keyIsDown = true
            DispatchQueue.main.async { self.onPress?() }
        } else if !active && keyIsDown {
            keyIsDown = false
            DispatchQueue.main.async { self.onRelease?() }
        }
    }
}
