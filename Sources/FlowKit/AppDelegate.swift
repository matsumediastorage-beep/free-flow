import AppKit
import ApplicationServices
import FluidAudio
import os

@MainActor
public final class AppDelegate: NSObject, NSApplicationDelegate {

    public override init() { super.init() }

    private let settings = Settings()
    private let history = HistoryStore()
    private let engine = ParakeetEngine()
    private let logger = Logger(subsystem: "com.matsumedia.flow", category: "app")

    private var dictation: DictationController!
    private var overlay: OverlayController!
    private var dashboard: DashboardWindowController!
    private var menuBar: MenuBarController!

    private let launchedAt = Date()

    private var modelLoadSeconds: Double = 0
    private var modelWarmupSeconds: Double = 0
    /// Launch to fully ready, the number that actually matters.
    private var readySeconds: Double = 0

    public func applicationDidFinishLaunching(_ notification: Notification) {
        applyActivationPolicy()

        dictation = DictationController(
            settings: settings,
            history: history,
            engine: engine
        )
        applyFormatter()

        // On a normal launch the weights are already on disk and loading is a
        // background detail — there's no reason to put a "Warming up" pill in
        // the middle of the screen for it. Only a first-run download, which
        // genuinely takes a while, is worth showing.
        let modelsCached = AsrModels.modelsExist(
            at: AsrModels.defaultCacheDirectory(for: .v3), version: .v3)
        overlay = OverlayController(controller: dictation, showsModelLoading: !modelsCached)

        dashboard = DashboardWindowController(
            history: history,
            settings: settings,
            dictation: dictation,
            onSettingsChanged: { [weak self] in
                self?.applyFormatter()
                self?.dictation.applySettings()
                self?.applyActivationPolicy()
            }
        )

        menuBar = MenuBarController(
            dictation: dictation,
            onOpenDashboard: { [weak self] in self?.dashboard.show() }
        )

        // Load the speech model regardless of permissions — it's a slow
        // first-run download, and there's no reason to make the user wait for
        // it after they finish granting access.
        dictation.onEngineReady = { [weak self] load, warmup in
            guard let self else { return }
            self.modelLoadSeconds = load
            self.modelWarmupSeconds = warmup
            self.readySeconds = Date().timeIntervalSince(self.launchedAt)
            self.writeStatus()
            self.menuBar.refresh()

            // Warm Apple's model too — its first generation costs ~3s cold —
            // but only *after* Parakeet is ready. Both run on the Neural
            // Engine, and warming them at the same time made each one slower.
            if self.settings.cleanupEngine != .off {
                Task.detached(priority: .utility) { await AppleFormatter.warmUp() }
            }
        }
        dictation.prepareEngine()

        startListening()

        // Permissions can only be granted while we're not frontmost, so
        // re-check whenever the user comes back from System Settings.
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.startListening()
                self?.menuBar.refresh()
            }
        }

        if !Permissions.allGranted {
            promptForMissingPermissions()
            dashboard.show()
        }
    }

    /// Starts the hotkey monitor once macOS will actually give us an event tap.
    ///
    /// Always refreshes the status file, even when already listening — otherwise
    /// `status.json` goes stale the moment the tap comes up and stops reflecting
    /// permission changes made while the app is running.
    private func startListening() {
        if !dictation.isListening, dictation.start() {
            logger.info("Hotkey monitor active (\(self.settings.hotkey.displayName))")
        }
        writeStatus()
    }

    /// Dock icon vs. menu bar only, per the user's setting.
    ///
    /// `.regular` shows in the Dock and Cmd-Tab; `.accessory` hides from both and
    /// leaves only the menu bar item. Either way the overlay stays
    /// non-activating, so dictation never steals focus.
    private func applyActivationPolicy() {
        let policy: NSApplication.ActivationPolicy = settings.showInDock ? .regular : .accessory
        guard NSApp.activationPolicy() != policy else { return }
        NSApp.setActivationPolicy(policy)
    }

    /// Clicking the Dock icon should open the dashboard, not just bounce.
    public func applicationShouldHandleReopen(
        _ sender: NSApplication, hasVisibleWindows: Bool
    ) -> Bool {
        dashboard.show()
        return true
    }

    /// Closing the dashboard shouldn't quit — Flow keeps listening in the
    /// background, which is the entire point of it.
    public func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    /// Asks macOS to show its own permission dialogs.
    ///
    /// This matters more than it looks: the system dialog registers the app in
    /// the Privacy list *itself*, with the right identity. Hunting for the right
    /// row in System Settings by hand is error-prone — especially with another
    /// app named "…Flow" installed, where it's easy to toggle the wrong one.
    private func promptForMissingPermissions() {
        for permission in Permissions.missing {
            Permissions.request(permission)
        }
    }

    /// Records what actually happened, so diagnosing "the hotkey does nothing"
    /// doesn't come down to guesswork.
    private func writeStatus() {

        LaunchStatus(
            launchedAt: launchedAt,
            accessibility: Permissions.isGranted(.accessibility),
            accessibilityBare: AXIsProcessTrusted(),
            inputMonitoring: Permissions.isGranted(.inputMonitoring),
            microphone: Permissions.isGranted(.microphone),
            hotkeyTapActive: dictation.isListening,
            hotkey: settings.hotkey.displayName,
            speechModelReady: dictation.isEngineReady,
            modelLoadSeconds: modelLoadSeconds,
            modelWarmupSeconds: modelWarmupSeconds,
            readySeconds: readySeconds,
            cleanupEngine: settings.cleanupEngine.rawValue,
            appleModelAvailable: AppleFormatter.isAvailable,
            appPath: Bundle.main.bundlePath
        ).write()
    }

    /// Picks the cleanup pass that matches the current settings.
    private func applyFormatter() {
        switch settings.cleanupEngine {
        case .off:
            dictation.formatter = PassthroughFormatter()

        case .onDevice:
            // Falls back to rule-based cleanup by itself if Apple Intelligence
            // is off or the model is still downloading.
            dictation.formatter = AppleFormatter()

        case .claude:
            if let key = KeychainStore.apiKey, !key.isEmpty {
                dictation.formatter = ClaudeFormatter(
                    apiKey: key,
                    fallback: AppleFormatter.isAvailable ? AppleFormatter() : LocalFormatter())
            } else {
                // Claude is selected but there's no key. Prefer the on-device
                // model over rule-based cleanup — it's free and already here.
                dictation.formatter =
                    AppleFormatter.isAvailable ? AppleFormatter() : LocalFormatter()
            }
        }
    }

    public func applicationWillTerminate(_ notification: Notification) {
        dictation.stop()
        history.save()
    }

    public func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool { true }
}
