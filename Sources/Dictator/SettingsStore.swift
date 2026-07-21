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

    struct AppTone: Codable, Identifiable, Hashable {
        var id = UUID()
        var appContains: String
        var tone: String
    }

    static let tones = ["casual", "neutral", "formal"]

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
    var llmEnabled: Bool {
        didSet { persist() }
    }
    var llmModel: String {
        didSet { persist() }
    }
    var defaultTone: String {
        didSet { persist() }
    }
    var appTones: [AppTone] {
        didSet { persist() }
    }

    func tone(forApp appName: String) -> String {
        let lowered = appName.lowercased()
        for entry in appTones {
            let needle = entry.appContains.trimmingCharacters(in: .whitespaces).lowercased()
            if !needle.isEmpty, lowered.contains(needle) {
                return entry.tone
            }
        }
        return defaultTone
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
        llmEnabled = defaults.object(forKey: "llmEnabled") as? Bool ?? true
        llmModel = defaults.string(forKey: "llmModel") ?? "qwen3:4b"
        defaultTone = defaults.string(forKey: "defaultTone") ?? "neutral"
        if let data = defaults.data(forKey: "appTones"),
           let decoded = try? JSONDecoder().decode([AppTone].self, from: data) {
            appTones = decoded
        } else {
            appTones = []
        }
    }

    private func persist() {
        let defaults = UserDefaults.standard
        if let data = try? JSONEncoder().encode(replacements) {
            defaults.set(data, forKey: "replacements")
        }
        defaults.set(removeFillers, forKey: "removeFillers")
        defaults.set(spokenCommands, forKey: "spokenCommands")
        defaults.set(llmEnabled, forKey: "llmEnabled")
        defaults.set(llmModel, forKey: "llmModel")
        defaults.set(defaultTone, forKey: "defaultTone")
        if let data = try? JSONEncoder().encode(appTones) {
            defaults.set(data, forKey: "appTones")
        }
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
