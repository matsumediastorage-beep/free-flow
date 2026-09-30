import ApplicationServices
import Foundation

/// Reads the text just before the cursor in whatever field has focus.
///
/// This is how the AI pass knows that "Blaire" should be "Blair" when the email
/// you're writing starts "Hi Blair,". It's the same Accessibility permission
/// Flow already needs to paste, and nothing is read unless you're dictating.
///
/// Guard rails, because this touches other apps:
///  * **Passwords are never read.** Secure text fields are skipped outright.
///  * **It can't hang.** Accessibility calls go to the other app's process and
///    block if that app is busy, so every call gets a short timeout and the
///    whole thing runs off the main thread.
///  * **It's best effort.** Many apps (some Electron and web fields) expose no
///    value at all; that just means no context, never an error.
enum FocusedTextContext {

    static func read(limit: Int = CleanupPrompt.contextLimit) async -> String? {
        await Task.detached(priority: .userInitiated) {
            FocusedTextContext.readSynchronously(limit: limit)
        }.value
    }

    static func readSynchronously(limit: Int) -> String? {
        let system = AXUIElementCreateSystemWide()
        AXUIElementSetMessagingTimeout(system, 0.15)

        var focusedRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                system, kAXFocusedUIElementAttribute as CFString, &focusedRef) == .success,
            let focusedRef, CFGetTypeID(focusedRef) == AXUIElementGetTypeID()
        else { return nil }
        let element = focusedRef as! AXUIElement
        AXUIElementSetMessagingTimeout(element, 0.15)

        if isSecure(element) { return nil }

        var valueRef: CFTypeRef?
        guard
            AXUIElementCopyAttributeValue(
                element, kAXValueAttribute as CFString, &valueRef) == .success,
            let text = valueRef as? String, !text.isEmpty
        else { return nil }

        let ns = text as NSString
        var end = ns.length

        // Where the cursor actually is, so text *after* it isn't mistaken for
        // what came before.
        var rangeRef: CFTypeRef?
        if AXUIElementCopyAttributeValue(
            element, kAXSelectedTextRangeAttribute as CFString, &rangeRef) == .success,
            let rangeRef, CFGetTypeID(rangeRef) == AXValueGetTypeID()
        {
            var range = CFRange()
            if AXValueGetValue(rangeRef as! AXValue, .cfRange, &range) {
                end = min(max(0, range.location), ns.length)
            }
        }

        let start = max(0, end - limit)
        let snippet = ns.substring(with: NSRange(location: start, length: end - start))
        return snippet.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : snippet
    }

    private static func isSecure(_ element: AXUIElement) -> Bool {
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        if let subrole = subrole as? String, subrole == (kAXSecureTextFieldSubrole as String) {
            return true
        }
        var role: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &role)
        if let role = role as? String, role.localizedCaseInsensitiveContains("secure") {
            return true
        }
        return false
    }

    /// Whether the dictated text needs a space in front of it to sit correctly
    /// after what's already there. "Hello" + "world" should paste " world".
    static func needsLeadingSpace(before: String?, inserting text: String) -> Bool {
        guard let before, let last = before.last, let first = text.first else { return false }
        if last.isWhitespace || last.isNewline { return false }
        if "([{\"'“‘/-@#".contains(last) { return false }
        if ".,!?;:)]}…".contains(first) { return false }
        return true
    }
}
