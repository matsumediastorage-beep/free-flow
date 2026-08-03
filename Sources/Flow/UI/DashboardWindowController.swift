import AppKit
import SwiftUI

/// Owns the dashboard window. Unlike the overlay, this one *is* allowed to take
/// focus — it's a normal window the user interacts with.
@MainActor
final class DashboardWindowController {

    private var window: NSWindow?
    private let history: HistoryStore
    private let settings: Settings
    private let onSettingsChanged: () -> Void

    init(
        history: HistoryStore,
        settings: Settings,
        onSettingsChanged: @escaping () -> Void
    ) {
        self.history = history
        self.settings = settings
        self.onSettingsChanged = onSettingsChanged
    }

    func show() {
        if window == nil {
            let view = DashboardView(
                history: history,
                settings: settings,
                onSettingsChanged: onSettingsChanged
            )

            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 680, height: 540),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Flow"
            window.titlebarAppearsTransparent = true
            window.contentView = NSHostingView(rootView: view)
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }

        // We're an accessory app, so we have to ask for activation explicitly.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
