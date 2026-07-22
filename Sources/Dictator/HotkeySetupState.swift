struct HotkeySetupState: Equatable {
    var listenerActive: Bool
    var accessibilityGranted: Bool

    var needsAccessibility: Bool {
        !accessibilityGranted
    }

    var shouldPromptForAccessibility: Bool {
        needsAccessibility
    }

    var showRecoveryActions: Bool {
        needsAccessibility || !listenerActive
    }

    var warningText: String? {
        if needsAccessibility {
            return "⚠️ Accessibility not granted — open settings to finish setup"
        }
        if !listenerActive {
            return "⚠️ Hotkey inactive — use Retry Hotkey Listener"
        }
        return nil
    }
}
