import AppKit

struct HistoryReturnTarget: Equatable {
    let processIdentifier: pid_t
    let bundleIdentifier: String?

    static func capture(
        frontmostProcessIdentifier: pid_t?,
        frontmostBundleIdentifier: String?,
        appProcessIdentifier: pid_t,
        appBundleIdentifier: String?
    ) -> HistoryReturnTarget? {
        guard let frontmostProcessIdentifier else { return nil }
        guard frontmostProcessIdentifier != appProcessIdentifier else { return nil }
        if let appBundleIdentifier, frontmostBundleIdentifier == appBundleIdentifier {
            return nil
        }
        return HistoryReturnTarget(
            processIdentifier: frontmostProcessIdentifier,
            bundleIdentifier: frontmostBundleIdentifier
        )
    }

    static func updated(
        current: HistoryReturnTarget?,
        activatedProcessIdentifier: pid_t?,
        activatedBundleIdentifier: String?,
        appProcessIdentifier: pid_t,
        appBundleIdentifier: String?
    ) -> HistoryReturnTarget? {
        capture(
            frontmostProcessIdentifier: activatedProcessIdentifier,
            frontmostBundleIdentifier: activatedBundleIdentifier,
            appProcessIdentifier: appProcessIdentifier,
            appBundleIdentifier: appBundleIdentifier
        ) ?? current
    }

    var runningApplication: NSRunningApplication? {
        NSRunningApplication(processIdentifier: processIdentifier)
    }
}
