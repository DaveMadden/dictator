import AppKit
import Carbon

/// Inserts text at the cursor of the frontmost app: swap the pasteboard,
/// synthesize ⌘V, restore the pasteboard shortly after.
final class Injector {
    /// Returns false when injection was refused (secure input field focused).
    @discardableResult
    func paste(_ text: String) -> Bool {
        guard !IsSecureEventInputEnabled() else {
            NSLog("Dictator: a secure input field (password entry) is focused — refusing to inject")
            return false
        }
        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)
        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        sendCmdV()
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
            self.restore(saved, to: pasteboard)
        }
        return true
    }

    private func sendCmdV() {
        let source = CGEventSource(stateID: .combinedSessionState)
        guard
            let down = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: true),
            let up = CGEvent(keyboardEventSource: source, virtualKey: CGKeyCode(kVK_ANSI_V), keyDown: false)
        else { return }
        down.flags = .maskCommand
        up.flags = .maskCommand
        down.post(tap: .cghidEventTap)
        up.post(tap: .cghidEventTap)
    }

    private func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        (pasteboard.pasteboardItems ?? []).map { item in
            var contents = [NSPasteboard.PasteboardType: Data]()
            for type in item.types {
                if let data = item.data(forType: type) {
                    contents[type] = data
                }
            }
            return contents
        }
    }

    private func restore(_ saved: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard) {
        pasteboard.clearContents()
        guard !saved.isEmpty else { return }
        let items = saved.map { contents -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in contents {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }
}
