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

    private typealias Snapshot = [[NSPasteboard.PasteboardType: Data]]

    private static let vKeyCode: CGKeyCode = 9  // kVK_ANSI_V

    /// How long to leave our text on the pasteboard before we put the user's
    /// original contents back.
    ///
    /// A posted ⌘V is only queued: nothing tells us when the target app gets
    /// to it and reads the pasteboard. Browsers, Electron apps and anything
    /// busy while the transcription finishes regularly take longer than a
    /// quarter second, and at 0.25s the restore won the race — they pasted
    /// the old clipboard instead of the dictation. Too long costs nothing
    /// worse than a manual ⌘V in that moment pasting the dictation again.
    private static let restoreDelay: TimeInterval = 1.5

    /// The user's real clipboard while a restore is waiting, and the change
    /// count of the text we wrote over it.
    private static var pendingRestore: (snapshot: Snapshot, changeCount: Int)?
    private static var restoreGeneration = 0

    static func insert(_ text: String) {
        guard !text.isEmpty else { return }

        let pasteboard = NSPasteboard.general

        // A restore still waiting means the pasteboard holds our last
        // dictation, not the user's clipboard — keep the snapshot from then.
        let saved: Snapshot
        if let pending = pendingRestore, pending.changeCount == pasteboard.changeCount {
            saved = pending.snapshot
        } else {
            saved = snapshot(of: pasteboard)
        }

        pasteboard.clearContents()
        pasteboard.setString(text, forType: .string)
        let changeCount = pasteboard.changeCount
        pendingRestore = (snapshot: saved, changeCount: changeCount)
        restoreGeneration += 1
        let generation = restoreGeneration

        paste()

        DispatchQueue.main.asyncAfter(deadline: .now() + restoreDelay) {
            // A newer insert has taken over the restore.
            guard generation == restoreGeneration else { return }
            pendingRestore = nil
            // Something was copied while we waited; that's the clipboard the
            // user wants now, so leave it alone.
            guard pasteboard.changeCount == changeCount else { return }
            restore(saved, to: pasteboard)
        }
    }

    // MARK: - Clipboard preservation

    /// Copies every representation of every item, so restoring gives back rich
    /// content (styled text, images, files) and not just a plain string.
    private static func snapshot(of pasteboard: NSPasteboard) -> Snapshot {
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

    private static func restore(_ snapshot: Snapshot, to pasteboard: NSPasteboard) {
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
