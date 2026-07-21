import Foundation
import Observation
import ServiceManagement

/// User preferences, UserDefaults-backed. The dictionary maps phrases as the
/// model hears them to how they should be written ("git hub" → "GitHub").
@Observable
final class SettingsStore {
    static let shared = SettingsStore()

    struct Replacement: Codable, Identifiable, Hashable {
        var id = UUID()
        var from: String
        var to: String
    }

    var replacements: [Replacement] {
        didSet { persist() }
    }
    var removeFillers: Bool {
        didSet { persist() }
    }
    var spokenCommands: Bool {
        didSet { persist() }
    }
    var launchAtLogin: Bool {
        didSet { applyLaunchAtLogin() }
    }

    private init() {
        let defaults = UserDefaults.standard
        if let data = defaults.data(forKey: "replacements"),
           let decoded = try? JSONDecoder().decode([Replacement].self, from: data) {
            replacements = decoded
        } else {
            replacements = []
        }
        removeFillers = defaults.object(forKey: "removeFillers") as? Bool ?? true
        spokenCommands = defaults.object(forKey: "spokenCommands") as? Bool ?? true
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(replacements) {
            defaults.set(data, forKey: "replacements")
        }
        defaults.set(removeFillers, forKey: "removeFillers")
        defaults.set(spokenCommands, forKey: "spokenCommands")
    }

    private func applyLaunchAtLogin() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            NSLog("Dictator: launch-at-login change failed: %@", "\(error)")
        }
    }
}
