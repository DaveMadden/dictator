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
    var llmModelPath: String {
        didSet { persist() }
    }
    var defaultTone: String {
        didSet { persist() }
    }
    var appTones: [AppTone] {
        didSet { persist() }
    }
    /// Custom folder for the Parakeet CoreML models; empty = default location.
    var speechModelDir: String {
        didSet { persist() }
    }
    /// Off by default: the app never downloads models unless this is enabled.
    var allowModelDownload: Bool {
        didSet { persist() }
    }

    static let defaultSpeechDir = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Dictator/models/parakeet-tdt-0.6b-v3-coreml", isDirectory: true)

    var resolvedSpeechDir: URL {
        let trimmed = speechModelDir.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return Self.defaultSpeechDir }
        return URL(fileURLWithPath: (trimmed as NSString).expandingTildeInPath, isDirectory: true)
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
        // Off by default: in real use the polish model fixed less than it
        // broke (unreliable self-corrections, paraphrasing, injection
        // obedience). Opt-in via Settings for anyone who wants to experiment.
        llmEnabled = defaults.object(forKey: "llmEnabled") as? Bool ?? false
        // The bare qwen3:4b tag resolves to a thinking-mode build that takes
        // minutes per reply; the instruct variant answers in ~1s.
        llmModel = defaults.string(forKey: "llmModel") ?? "qwen3:4b-instruct"
        llmModelPath = defaults.string(forKey: "llmModelPath") ?? ""
        defaultTone = defaults.string(forKey: "defaultTone") ?? "neutral"
        if let data = defaults.data(forKey: "appTones"),
           let decoded = try? JSONDecoder().decode([AppTone].self, from: data) {
            appTones = decoded
        } else {
            appTones = []
        }
        speechModelDir = defaults.string(forKey: "speechModelDir") ?? ""
        allowModelDownload = defaults.object(forKey: "allowModelDownload") as? Bool ?? false
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
        defaults.set(llmModelPath, forKey: "llmModelPath")
        defaults.set(defaultTone, forKey: "defaultTone")
        if let data = try? JSONEncoder().encode(appTones) {
            defaults.set(data, forKey: "appTones")
        }
        defaults.set(speechModelDir, forKey: "speechModelDir")
        defaults.set(allowModelDownload, forKey: "allowModelDownload")
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
