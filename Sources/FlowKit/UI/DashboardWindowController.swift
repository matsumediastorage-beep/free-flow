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
                contentRect: NSRect(x: 0, y: 0, width: 780, height: 560),
                styleMask: [.titled, .closable, .miniaturizable, .resizable, .fullSizeContentView],
                backing: .buffered,
                defer: false
            )
            window.title = "Free Flow"
            window.titlebarAppearsTransparent = true

            // NavigationSplitView only vends its sidebar toggle — and
            // `.searchable(placement: .toolbar)` only has anywhere to go — if
            // the window actually owns a toolbar. Without one you get a bare
            // title bar and the search field silently falls back into the
            // content area.
            let toolbar = NSToolbar(identifier: "FlowDashboard")
            toolbar.displayMode = .iconOnly
            toolbar.allowsUserCustomization = false
            window.toolbar = toolbar
            window.toolbarStyle = .unified

            window.contentView = NSHostingView(rootView: view)
            window.setFrameAutosaveName("FlowDashboard")
            window.center()
            window.isReleasedWhenClosed = false
            self.window = window
        }

        // We're an accessory app, so we have to ask for activation explicitly.
        NSApp.activate(ignoringOtherApps: true)
        window?.makeKeyAndOrderFront(nil)
    }
}
