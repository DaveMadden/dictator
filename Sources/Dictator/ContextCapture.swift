import AppKit
import ApplicationServices
import DictatorLLM

enum ContextCapture {
    static func capture() -> DictationContext {
        let appName = NSWorkspace.shared.frontmostApplication?.localizedName ?? "unknown"
        return DictationContext(appName: appName, precedingText: precedingText())
    }

    private static func precedingText(limit: Int = 400) -> String {
        let system = AXUIElementCreateSystemWide()
        var focusedRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                system, kAXFocusedUIElementAttribute as CFString, &focusedRef
            ) == .success,
            let focused = focusedRef,
            CFGetTypeID(focused) == AXUIElementGetTypeID()
        else { return "" }
        let element = unsafeDowncast(focused as AnyObject, to: AXUIElement.self)

        var valueRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(element, kAXValueAttribute as CFString, &valueRef) == .success,
            let text = valueRef as? String, !text.isEmpty
        else { return "" }
        let nsText = text as NSString

        var cursor = nsText.length
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef
        ) == .success,
            let rangeValue = rangeRef,
            CFGetTypeID(rangeValue) == AXValueGetTypeID() {
            var range = CFRange()
            if AXValueGetValue(unsafeDowncast(rangeValue as AnyObject, to: AXValue.self), .cfRange, &range) {
                cursor = min(max(0, range.location), nsText.length)
            }
        }

        let start = max(0, cursor - limit)
        return nsText.substring(with: NSRange(location: start, length: cursor - start))
    }
}
