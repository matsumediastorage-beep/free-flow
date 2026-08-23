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
    @State private var newVocabularyTerm = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var cleanupStatus = CleanupStatus.read()
    @State private var isTesting = false

    var body: some View {
        Form {
            dictationKeySection
            cleanupSection
            vocabularySection
            generalSection
        }
        .formStyle(.grouped)
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
                cleanupStatusRow
            }
        } header: {
            Text("AI cleanup")
        } footer: {
            Text(
                "Cleanup removes filler words, adds punctuation, applies spoken corrections, and formats lists. It only ever reformats — it will never answer a question you dictate. If it's slow, offline or unavailable, Flow pastes the raw transcript instead, so it can never block your text."
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

        HStack {
            Button(isTesting ? "Testing…" : "Test cleanup now") { runCleanupTest() }
                .disabled(isTesting || settings.cleanupEngine == .off)
            if isTesting {
                ProgressView().controlSize(.small).scaleEffect(0.7)
            }
        }
    }

    // MARK: - Vocabulary

    private var vocabularySection: some View {
        Section {
            HStack {
                TextField("Add a word or name", text: $newVocabularyTerm)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(addTerm)
                Button("Add", action: addTerm)
                    .disabled(newVocabularyTerm.trimmingCharacters(in: .whitespaces).isEmpty)
            }

            if !settings.vocabulary.isEmpty {
                WrappingChips(items: settings.vocabulary) { term in
                    settings.vocabulary.removeAll { $0 == term }
                }
            }
        } header: {
            Text("Vocabulary")
        } footer: {
            Text(
                "Names, clients and jargon Flow should spell correctly — useful for anything the speech model is likely to garble."
            )
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
        Task {
            _ = await formatter.format(
                "um so like can you send me the uh the file tomorrow ok",
                context: FormattingContext(appName: nil, vocabulary: settings.vocabulary)
            )
            cleanupStatus = CleanupStatus.read()
            isTesting = false
        }
    }

    private func saveKey() {
        KeychainStore.apiKey = apiKey.trimmingCharacters(in: .whitespacesAndNewlines)
        onSettingsChanged()
    }

    private func addTerm() {
        let term = newVocabularyTerm.trimmingCharacters(in: .whitespaces)
        guard !term.isEmpty, !settings.vocabulary.contains(term) else { return }
        settings.vocabulary.append(term)
        newVocabularyTerm = ""
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

/// Simple flow layout for the vocabulary chips.
private struct WrappingChips: View {
    let items: [String]
    let onRemove: (String) -> Void

    var body: some View {
        FlowLayout(spacing: 6) {
            ForEach(items, id: \.self) { item in
                HStack(spacing: 4) {
                    Text(item).font(.system(size: 11))
                    Button {
                        onRemove(item)
                    } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 8, weight: .bold))
                    }
                    .buttonStyle(.borderless)
                    .foregroundStyle(.secondary)
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 4)
                .background(Capsule().fill(.quaternary))
            }
        }
    }
}

private struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
        return CGSize(width: maxWidth, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
