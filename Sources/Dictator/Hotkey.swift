import CoreGraphics
import Foundation

/// Push-to-talk keys. All are modifier-style keys that arrive as flagsChanged
/// events, identified by keycode so left/right variants stay distinct.
enum Hotkey: String, CaseIterable {
    case fn
    case rightShift
    case rightCommand
    case rightOption

    static let defaultsKey = "hotkey"

    var title: String {
        switch self {
        case .fn: return "fn (globe)"
        case .rightShift: return "Right Shift"
        case .rightCommand: return "Right Command"
        case .rightOption: return "Right Option"
        }
    }

    var keyCode: Int64 {
        switch self {
        case .fn: return 63           // kVK_Function
        case .rightShift: return 60   // kVK_RightShift
        case .rightCommand: return 54 // kVK_RightCommand
        case .rightOption: return 61  // kVK_RightOption
        }
    }

    var flag: CGEventFlags {
        switch self {
        case .fn: return .maskSecondaryFn
        case .rightShift: return .maskShift
        case .rightCommand: return .maskCommand
        case .rightOption: return .maskAlternate
        }
    }

    static var saved: Hotkey {
        UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(Hotkey.init(rawValue:)) ?? .fn
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}

/// How the hotkey drives a dictation: hold-to-talk (press = start,
/// release = stop) or toggle (tap to start, tap again to stop).
enum ActivationMode: String, CaseIterable {
    case hold
    case toggle

    static let defaultsKey = "activationMode"

    var title: String {
        switch self {
        case .hold: return "Hold to Talk"
        case .toggle: return "Toggle (tap to start/stop)"
        }
    }

    static var saved: ActivationMode {
        UserDefaults.standard.string(forKey: defaultsKey)
            .flatMap(ActivationMode.init(rawValue:)) ?? .hold
    }

    func save() {
        UserDefaults.standard.set(rawValue, forKey: Self.defaultsKey)
    }
}
