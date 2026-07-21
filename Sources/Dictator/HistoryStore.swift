import Foundation
import Observation

/// Local-only dictation history: a JSON file in Application Support, capped
/// at 500 entries. Never leaves the machine; one click wipes it.
@Observable
final class HistoryStore {
    static let shared = HistoryStore()
    static let maxEntries = 500

    struct Entry: Codable, Identifiable {
        var id = UUID()
        let date: Date
        let app: String
        let raw: String
        let text: String
    }

    private(set) var entries: [Entry] = []

    private static let fileURL = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Dictator/history.json")

    private init() {
        if let data = try? Data(contentsOf: Self.fileURL),
           let decoded = try? JSONDecoder().decode([Entry].self, from: data) {
            entries = decoded
        }
    }

    func add(raw: String, text: String, app: String) {
        entries.append(Entry(date: Date(), app: app, raw: raw, text: text))
        if entries.count > Self.maxEntries {
            entries.removeFirst(entries.count - Self.maxEntries)
        }
        persist()
    }

    func clear() {
        entries.removeAll()
        persist()
    }

    private func persist() {
        let snapshot = entries
        DispatchQueue.global(qos: .utility).async {
            guard let data = try? JSONEncoder().encode(snapshot) else { return }
            let dir = Self.fileURL.deletingLastPathComponent()
            try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try? data.write(to: Self.fileURL, options: .atomic)
        }
    }
}
