import AppKit

/// The menu bar item: Flow's only persistent UI when idle.
@MainActor
final class MenuBarController: NSObject, NSMenuDelegate {

    private let statusItem: NSStatusItem
    private let menu = NSMenu()
    private let dictation: DictationController
    private let onOpenDashboard: () -> Void

    init(dictation: DictationController, onOpenDashboard: @escaping () -> Void) {
        self.dictation = dictation
        self.onOpenDashboard = onOpenDashboard
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)

        super.init()

        statusItem.menu = menu
        menu.delegate = self
        refresh()

        // Reflect recording state in the menu bar icon.
        let existing = dictation.onStateChange
        dictation.onStateChange = { [weak self] state in
            existing?(state)
            self?.updateIcon(for: state)
        }
    }

    func refresh() {
        updateIcon(for: dictation.state)
        rebuildMenu()
    }

    private func updateIcon(for state: DictationState) {
        guard let button = statusItem.button else { return }

        let symbol: String
        switch state {
        case .listening: symbol = "waveform.circle.fill"
        case .transcribing: symbol = "waveform.circle"
        case .failed: symbol = "exclamationmark.triangle"
        case .preparing: symbol = "arrow.down.circle"
        case .idle, .finished:
            symbol = Permissions.allGranted ? "waveform" : "exclamationmark.triangle"
        }

        button.image = NSImage(systemSymbolName: symbol, accessibilityDescription: "Free Flow")
        button.image?.isTemplate = true
    }

    private func rebuildMenu() {
        menu.removeAllItems()

        let missing = Permissions.missing
        if missing.isEmpty {
            addDisabled("Hold \(dictation.hotkeyName) to dictate")
        } else {
            addDisabled("Setup needed — \(missing.count) permission\(missing.count == 1 ? "" : "s")")
            for permission in missing {
                let item = NSMenuItem(
                    title: "Grant \(permission.title)…",
                    action: #selector(grantPermission(_:)),
                    keyEquivalent: ""
                )
                item.target = self
                item.representedObject = permission.rawValue
                menu.addItem(item)
            }
        }

        switch dictation.state {
        case .preparing(.loading(let fraction)):
            addDisabled("Loading speech model… \(Int(fraction * 100))%")
        case .preparing(.warming):
            addDisabled("Warming up the speech model…")
        default:
            break
        }
        if dictation.isHandsFree {
            addDisabled("Hands-free mode on")
        }

        menu.addItem(.separator())

        let dashboardItem = NSMenuItem(
            title: "Dashboard…", action: #selector(openDashboard), keyEquivalent: "d")
        dashboardItem.target = self
        menu.addItem(dashboardItem)

        menu.addItem(.separator())
        menu.addItem(
            NSMenuItem(
                title: "Quit Flow",
                action: #selector(NSApplication.terminate(_:)),
                keyEquivalent: "q"))
    }

    private func addDisabled(_ title: String) {
        let item = NSMenuItem(title: title, action: nil, keyEquivalent: "")
        item.isEnabled = false
        menu.addItem(item)
    }

    // MARK: - Actions

    @objc private func grantPermission(_ sender: NSMenuItem) {
        guard let raw = sender.representedObject as? String,
            let permission = Permission(rawValue: raw)
        else { return }
        Permissions.request(permission)
        Permissions.openSettings(for: permission)
    }

    @objc private func openDashboard() {
        onOpenDashboard()
    }

    // MARK: - NSMenuDelegate

    func menuWillOpen(_ menu: NSMenu) {
        refresh()
    }
}
