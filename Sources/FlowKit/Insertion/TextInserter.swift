import AppKit
import CoreGraphics

/// Puts text into whatever app currently has focus.
///
/// Method: stash the user's clipboard, put our text on it, synthesize ⌘V, then
/// restore. This is the only approach that works universally — the Accessibility
/// `AXSelectedText` API silently fails in Electron and browser text fields, and
/// typing the string out as synthetic keystrokes is slow and drops characters.
@MainActor
enum TextInserter {

    private static let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V

    /// How long to let the target app read the pasteboard before we put the
    /// user's original contents back.
    private static let restoreDelay: TimeInterval = 0.25

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general
        let saved = snapshot(of: pasteboard)

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)

        paste()

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            restore(saved, to: pasteboard)
        }
    }

    // MARK: - Clipboard preservation

    /// Copies every representation of every item, so restoring gives back rich
    /// content (styled text, images, files) and not just a plain string.
    private static func snapshot(of pasteboard: NSPasteboard) -> [[NSPasteboard.PasteboardType: Data]] {
        guard let items = pasteboard.pasteboardItems else { return [] }
        return items.map { item in
            var representations: [NSPasteboard.PasteboardType: Data] = [:]
            for type in item.types {
                if let data = item.data(forType: type) {
                    representations[type] = data
                }
            }
            return representations
        }
    }

    private static func restore(
        _ snapshot: [[NSPasteboard.PasteboardType: Data]], to pasteboard: NSPasteboard
    ) {
        pasteboard.clearContents()
        guard !snapshot.isEmpty else { return }

        let items = snapshot.map { representations -> NSPasteboardItem in
            let item = NSPasteboardItem()
            for (type, data) in representations {
                item.setData(data, forType: type)
            }
            return item
        }
        pasteboard.writeObjects(items)
    }

    // MARK: - Synthetic ⌘V

    private static func paste() {
        guard let source = CGEventSource(stateID: .combinedSessionState) else { return }

        // Don't let our synthetic events inherit the physically-held modifiers.
        // Without this, a still-held Shift turns ⌘V into ⌘⇧V ("paste and match
        // style", or worse depending on the app).
        source.setLocalEventsFilterDuringSuppressionState(
            [.permitLocalMouseEvents, .permitSystemDefinedEvents],
            state: .eventSuppressionStateSuppressionInterval
        )

        let keyDown = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: true)
        let keyUp = CGEvent(keyboardEventSource: source, virtualKey: vKeyCode, keyDown: false)

        // Assigning flags explicitly overrides the real keyboard state.
        keyDown?.flags = .maskCommand
        keyUp?.flags = .maskCommand

        keyDown?.post(tap: .cghidEventTap)
        keyUp?.post(tap: .cghidEventTap)
    }
}
