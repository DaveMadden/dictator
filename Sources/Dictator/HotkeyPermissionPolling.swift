struct HotkeyPermissionPollOutcome: Equatable {
    let listenerActive: Bool
    let stopPolling: Bool

    static func evaluate(
        accessibilityGranted: Bool,
        startSucceeded: Bool
    ) -> HotkeyPermissionPollOutcome? {
        guard accessibilityGranted else { return nil }
        if startSucceeded {
            return HotkeyPermissionPollOutcome(listenerActive: true, stopPolling: true)
        }
        return HotkeyPermissionPollOutcome(listenerActive: false, stopPolling: false)
    }
}
