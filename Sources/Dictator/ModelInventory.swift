import FluidAudio
import Foundation
#if DICTATOR_LLM
import DictatorLLM
#endif

/// What models exist on disk for each role — powers Settings → Models.
enum ModelInventory {
    struct SpeechStatus {
        let found: Bool
        let detail: String
    }

    struct LLMItem: Identifiable {
        let url: URL
        let sizeBytes: Int64
        let active: Bool
        var id: String { url.path }
        var name: String { url.lastPathComponent }
        var sizeText: String { ModelInventory.sizeText(sizeBytes) }
    }

    static func speechStatus() -> SpeechStatus {
        let configured = SettingsStore.shared.resolvedSpeechDir
        if AsrModels.modelsExist(at: configured) {
            return SpeechStatus(
                found: true,
                detail: "Parakeet TDT v3 · \(sizeText(directorySize(configured))) · \(abbreviate(configured))"
            )
        }
        let cache = AsrModels.defaultCacheDirectory()
        if AsrModels.modelsExist(at: cache) {
            return SpeechStatus(
                found: true,
                detail: "Parakeet TDT v3 · \(sizeText(directorySize(cache))) · download cache"
            )
        }
        return SpeechStatus(
            found: false,
            detail: "Not found — run make install-models-from-repo, or point at your folder below"
        )
    }

    /// Every polish candidate the app can see: whatever the configured path
    /// resolves to, plus anything in the standard sideload folder.
    #if DICTATOR_LLM
    static func llmItems() -> [LLMItem] {
        let path = SettingsStore.shared.llmModelPath.trimmingCharacters(in: .whitespaces)
        let active = LlamaEngine.resolveModelURL(customPath: path)
        var urls: [URL] = []
        if !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            if FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) {
                let url = URL(fileURLWithPath: expanded)
                urls = isDirectory.boolValue ? LlamaEngine.availableModels(in: url) : [url]
            }
        }
        var seen = Set(urls.map(\.path))
        for candidate in LlamaEngine.availableModels() where !seen.contains(candidate.path) {
            urls.append(candidate)
            seen.insert(candidate.path)
        }
        return urls.map { url in
            LLMItem(url: url, sizeBytes: fileSize(url), active: url.path == active?.path)
        }
    }
    #else
    static func llmItems() -> [LLMItem] { [] }
    #endif

    static func abbreviate(_ url: URL) -> String {
        url.path.replacingOccurrences(of: NSHomeDirectory(), with: "~")
    }

    static func sizeText(_ bytes: Int64) -> String {
        ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
    }

    private static func fileSize(_ url: URL) -> Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? 0
    }

    private static func directorySize(_ url: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: url, includingPropertiesForKeys: [.fileSizeKey]
        ) else { return 0 }
        var total: Int64 = 0
        for case let fileURL as URL in enumerator {
            let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            total += Int64(size)
        }
        return total
    }
}
