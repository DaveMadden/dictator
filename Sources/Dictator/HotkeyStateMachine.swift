import CoreGraphics

enum HotkeyTapAction: Equatable {
    case enableGuardTap
    case disableGuardTap
    case reenableMonitorTap
    case reenableGuardTap
}

struct HotkeyEventOutcome: Equatable {
    var emitPress = false
    var emitRelease = false
    var emitLock = false
    var swallowEvent = false
    var tapActions: [HotkeyTapAction] = []
}

final class HotkeyStateMachine {
    static let spaceKeyCode: Int64 = 49

    var hotkey: Hotkey = .fn {
        didSet { reset() }
    }

    private var keyIsDown = false
    private var swallowSpaceUp = false

    func reset() {
        keyIsDown = false
        swallowSpaceUp = false
    }

    func handleMonitorEvent(
        type: CGEventType,
        keyCode: Int64,
        flags: CGEventFlags
    ) -> HotkeyEventOutcome {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return HotkeyEventOutcome(tapActions: [.reenableMonitorTap])
        }
        guard type == .flagsChanged, keyCode == hotkey.keyCode else {
            return HotkeyEventOutcome()
        }

        let active = flags.contains(hotkey.flag)
        if active && !keyIsDown {
            keyIsDown = true
            return HotkeyEventOutcome(
                emitPress: true,
                tapActions: [.enableGuardTap]
            )
        }
        if !active && keyIsDown {
            keyIsDown = false
            let actions: [HotkeyTapAction] = swallowSpaceUp ? [] : [.disableGuardTap]
            return HotkeyEventOutcome(
                emitRelease: true,
                tapActions: actions
            )
        }
        return HotkeyEventOutcome()
    }

    func handleGuardEvent(type: CGEventType, keyCode: Int64) -> HotkeyEventOutcome {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            return HotkeyEventOutcome(tapActions: [.reenableGuardTap])
        }

        switch type {
        case .keyDown:
            guard keyIsDown, keyCode == Self.spaceKeyCode else {
                return HotkeyEventOutcome()
            }
            swallowSpaceUp = true
            return HotkeyEventOutcome(
                emitLock: true,
                swallowEvent: true
            )
        case .keyUp:
            guard swallowSpaceUp, keyCode == Self.spaceKeyCode else {
                return HotkeyEventOutcome()
            }
            swallowSpaceUp = false
            let actions: [HotkeyTapAction] = keyIsDown ? [] : [.disableGuardTap]
            return HotkeyEventOutcome(
                swallowEvent: true,
                tapActions: actions
            )
        default:
            return HotkeyEventOutcome()
        }
    }
}
