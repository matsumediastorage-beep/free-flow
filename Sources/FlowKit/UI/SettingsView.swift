import AppKit
import ServiceManagement
import SwiftUI

/// Settings, as a grouped form.
///
/// The explanatory text lives in `Section` footers rather than as loose captions
/// between the controls. That's the native pattern — it lets AppKit align and
/// tint it, and it stops the form reading as a wall of small grey paragraphs.
struct SettingsView: View {
    @Bindable var settings: Settings
    let history: HistoryStore
    let onSettingsChanged: () -> Void

    @State private var apiKey: String = KeychainStore.apiKey ?? ""
    @State private var lastTestResult: String?
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cleanupStatus = CleanupStatus.read()
    @State private var isTesting = false

    var body: some View {
        Form {
            dictationKeySection
            cleanupSection
            generalSection
        }
        .formStyle(.grouped)
        .tint(Theme.violet)
    }

    // MARK: - Dictation key

    private var dictationKeySection: some View {
        Section {
            Picker("Hold to talk", selection: $settings.hotkey) {
                ForEach(Hotkey.allCases, id: \.self) { key in
                    Text(key.displayName).tag(key)
                }
            }
            .onChange(of: settings.hotkey) { _, _ in onSettingsChanged() }

            LabeledContent("Hold delay") {
                HStack(spacing: 10) {
                    Slider(value: $settings.holdThreshold, in: 0.15...0.6, step: 0.05)
                        .frame(minWidth: 130)
                        .onChange(of: settings.holdThreshold) { _, _ in onSettingsChanged() }
                    Text("\(settings.holdThreshold, specifier: "%.2f")s")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .frame(width: 42, alignment: .trailing)
                }
            }

            if settings.hotkey.needsTypingGuard {
                Callout(
                    symbol: "info.circle.fill",
                    tint: .blue,
                    title: "\(settings.hotkey.displayName) is also how you type capitals.",
                    detail:
                        "Flow waits out the hold delay and cancels the moment you press another key, so Shift+A still just types A. Right Option and Fn have no typing conflict at all."
                )
            }
        } header: {
            Text("Dictation key")
        } footer: {
            Text("Double-tap the same key for hands-free mode, then tap again to stop.")
        }
    }

    // MARK: - AI cleanup

    private var cleanupSection: some View {
        Section {
            Picker("Clean up my speech", selection: $settings.cleanupEngine) {
                ForEach(CleanupEngine.allCases, id: \.self) { engine in
                    Text(engine.title).tag(engine)
                }
            }
            .pickerStyle(.segmented)
            .onChange(of: settings.cleanupEngine) { _, _ in onSettingsChanged() }

            Text(settings.cleanupEngine.detail)
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            switch settings.cleanupEngine {
            case .off:
                EmptyView()
            case .onDevice:
                onDeviceStatus
            case .claude:
                claudeControls
            }

            if settings.cleanupEngine != .off {
                Picker("Style", selection: $settings.cleanupStyle) {
                    ForEach(CleanupStyle.allCases, id: \.self) { style in
                        Text(style.title).tag(style)
                    }
                }
                .pickerStyle(.segmented)

                Text(settings.cleanupStyle.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Toggle(isOn: $settings.useScreenContext) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use the text around my cursor")
                        Text(
                            "Reads what's already typed before the cursor so misheard names get fixed from context. Password fields are never read."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }

            if settings.cleanupEngine != .off {
                cleanupStatusRow
            }
        } header: {
            Text("AI cleanup")
        } footer: {
            Text(
                "Cleanup fixes words the speech model misheard, removes fillers, adds punctuation and applies spoken corrections. It only ever edits what you said; it will never answer a question you dictate. If Claude is slow or offline, Free Flow falls back to Apple's model or the raw transcript, so it can never block your text."
            )
        }
    }

    /// The on-device model needs no configuration, so the only thing worth
    /// saying is whether macOS will actually hand it over.
    @ViewBuilder
    private var onDeviceStatus: some View {
        if let reason = AppleFormatter.unavailableReason {
            Callout(
                symbol: "exclamationmark.triangle.fill",
                tint: .orange,
                title: "The on-device model isn't available.",
                detail: "\(reason) Until it is, Flow falls back to basic local cleanup."
            ) {
                Button("Open Apple Intelligence settings") {
                    if let url = URL(
                        string:
                            "x-apple.systempreferences:com.apple.preference.security?AppleIntelligence"
                    ) {
                        NSWorkspace.shared.open(url)
                    }
                }
                .controlSize(.small)
            }
        } else {
            Callout(
                symbol: "checkmark.seal.fill",
                tint: .green,
                title: "Ready — no key, no cost, nothing leaves this Mac.",
                detail:
                    "Apple Intelligence is on and the model is loaded. This works offline."
            )
        }
    }

    @ViewBuilder
    private var claudeControls: some View {
        LabeledContent("API key") {
            SecureField("", text: $apiKey, prompt: Text("sk-ant-…"))
                .textFieldStyle(.roundedBorder)
                .frame(minWidth: 200)
                .onSubmit(saveKey)
                .onChange(of: apiKey) { _, _ in saveKey() }
        }

        if !KeychainStore.hasAPIKey {
            Callout(
                symbol: "key",
                tint: .orange,
                title: "No key yet.",
                detail:
                    "Without one, Flow uses the free on-device model instead — which is a perfectly good place to stay."
            ) {
                Link(
                    "Create an API key",
                    destination: URL(string: "https://console.anthropic.com/settings/keys")!
                )
                .font(.caption)
            }
        }
    }

    /// Cleanup failures are silent by design so they never block a paste —
    /// which makes a broken key, or a switched-off Apple Intelligence, invisible.
    /// This is where it becomes visible.
    @ViewBuilder
    private var cleanupStatusRow: some View {
        if let status = cleanupStatus {
            HStack(alignment: .top, spacing: 8) {
                Image(
                    systemName: status.succeeded
                        ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .foregroundStyle(status.succeeded ? .green : .orange)
                .contentTransition(.symbolEffect(.replace))

                VStack(alignment: .leading, spacing: 2) {
                    Text(status.succeeded ? "Last cleanup worked" : "Last cleanup failed")
                        .font(.callout.weight(.medium))
                    Text(status.detail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(
                        "\(status.at.formatted(date: .abbreviated, time: .shortened)) · \(status.seconds, specifier: "%.2f")s"
                    )
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.tertiary)
                }
                Spacer(minLength: 0)
            }
            .animation(.snappy(duration: 0.25), value: status.succeeded)
        }

        if let lastTestResult {
            VStack(alignment: .leading, spacing: 4) {
                Text("You said: \"\(Self.testPhrase)\"")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(lastTestResult)
                    .font(.callout.weight(.medium))
                    .textSelection(.enabled)
            }
        }

        HStack {
            Button(isTesting ? "Testing…" : "Test cleanup now") { runCleanupTest() }
                .disabled(isTesting || settings.cleanupEngine == .off)
            if isTesting {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
        }
    }

    // MARK: - General

    private var generalSection: some View {
        Section {
            Toggle("Show icon in the Dock", isOn: $settings.showInDock)
                .onChange(of: settings.showInDock) { _, _ in onSettingsChanged() }

            Toggle("Launch at login", isOn: $launchAtLogin)
                .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }

            Toggle("Play a sound when recording starts", isOn: $settings.playSounds)

            Picker("Keep history", selection: $settings.retentionDays) {
                Text("Forever").tag(0)
                Text("30 days").tag(30)
                Text("90 days").tag(90)
                Text("1 year").tag(365)
            }

            Button("Clear history (keeps pinned)", role: .destructive) {
                history.clearUnpinned()
            }
        } header: {
            Text("General")
        } footer: {
            Text(
                "Launch at login is worth leaving on: the speech model takes a few seconds to load, and starting at boot means you never wait for it."
            )
        }
    }

    // MARK: - Actions

    /// Sends one throwaway request so a broken key surfaces here, on demand,
    /// instead of silently degrading every dictation.
    private func runCleanupTest() {
        let formatter: any TextFormatter
        switch settings.cleanupEngine {
        case .off:
            return
        case .onDevice:
            formatter = AppleFormatter(fallback: PassthroughFormatter())
        case .claude:
            guard let key = KeychainStore.apiKey, !key.isEmpty else { return }
            formatter = ClaudeFormatter(apiKey: key, fallback: PassthroughFormatter())
        }
        isTesting = true
        let context = FormattingContext(
            appName: nil,
            vocabulary: settings.vocabulary,
            precedingText: nil,
            style: settings.cleanupStyle
        )
        Task {
            let result = await formatter.format(Self.testPhrase, context: context)
            lastTestResult = result
            cleanupStatus = CleanupStatus.read()
            isTesting = false
        }
    }

    /// A realistic messy dictation: fillers, a false start, a self-correction,
    /// and a homophone the model has to fix from context.
    static let testPhrase =
        "um so I wanted to to let you know that there meeting is on tuesday no wait thursday at like three thirty"

    private func saveKey() {
        KeychainStore.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        onSettingsChanged()
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            // Revert the toggle so it reflects reality.
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

/// An inline note with an icon — the shape macOS uses for "here's something you
/// should know" without escalating to an alert.
private struct Callout<Accessory: View>: View {
    let symbol: String
    let tint: Color
    let title: String
    let detail: String
    @ViewBuilder var accessory: () -> Accessory

    init(
        symbol: String,
        tint: Color,
        title: String,
        detail: String,
        @ViewBuilder accessory: @escaping () -> Accessory = { EmptyView() }
    ) {
        self.symbol = symbol
        self.tint = tint
        self.title = title
        self.detail = detail
        self.accessory = accessory
    }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: symbol)
                .foregroundStyle(tint)
                .font(.system(size: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                accessory()
            }
            Spacer(minLength: 0)
        }
    }
}
