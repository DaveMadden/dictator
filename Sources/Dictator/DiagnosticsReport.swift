import Foundation

struct DiagnosticsReport: Equatable {
    let timestamp: Date
    let appVersion: String
    let buildVersion: String
    let bundlePath: String
    let processID: Int32
    let hotkeyTitle: String
    let activationTitle: String
    let dictationState: String
    let sessionLocked: Bool
    let hotkeyListenerActive: Bool
    let accessibilityGranted: Bool
    let inputMonitoringGranted: Bool
    let microphonePermission: String
    let launchAtLoginEnabled: Bool
    let modelStatus: String
    let polishStatus: String
    let historyCount: Int
    let lastHistoryApp: String?
    let lastHistoryDate: Date?
    let setupWarning: String?

    var formatted: String {
        var lines = [
            "Dictator Diagnostics",
            "timestamp: \(Self.dateFormatter.string(from: timestamp))",
            "app version: \(appVersion) (\(buildVersion))",
            "bundle path: \(bundlePath)",
            "pid: \(processID)",
            "hotkey: \(hotkeyTitle)",
            "activation: \(activationTitle)",
            "dictation state: \(dictationState)",
            "session locked: \(sessionLocked)",
            "hotkey listener active: \(hotkeyListenerActive)",
            "accessibility granted: \(accessibilityGranted)",
            "input monitoring granted: \(inputMonitoringGranted)",
            "microphone permission: \(microphonePermission)",
            "launch at login: \(launchAtLoginEnabled)",
            "model status: \(modelStatus)",
            "ai polish status: \(polishStatus)",
            "history count: \(historyCount)"
        ]

        if let lastHistoryApp {
            lines.append("last dictation app: \(lastHistoryApp)")
        } else {
            lines.append("last dictation app: none")
        }

        if let lastHistoryDate {
            lines.append("last dictation at: \(Self.dateFormatter.string(from: lastHistoryDate))")
        } else {
            lines.append("last dictation at: none")
        }

        if let setupWarning {
            lines.append("setup warning: \(setupWarning)")
        } else {
            lines.append("setup warning: none")
        }

        lines.append("note: transcript text omitted for privacy")
        return lines.joined(separator: "\n")
    }

    private static let dateFormatter: ISO8601DateFormatter = {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter
    }()
}
