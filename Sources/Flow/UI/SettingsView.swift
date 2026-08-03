import ServiceManagement
import SwiftUI

struct SettingsView: View {
    @Bindable var settings: Settings
    let history: HistoryStore
    let onSettingsChanged: () -> Void

    @State private var apiKey: String = KeychainStore.apiKey ?? ""
    @State private var newVocabularyTerm = ""
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

    var body: some View {
        Form {
            Section("Dictation key") {
                Picker("Hold to talk", selection: $settings.hotkey) {
                    ForEach(Hotkey.allCases, id: \.self) { key in
                        Text(key.displayName).tag(key)
                    }
                }
                .onChange(of: settings.hotkey) { _, _ in onSettingsChanged() }

                VStack(alignment: .leading, spacing: 4) {
                    Slider(value: $settings.holdThreshold, in: 0.15...0.6, step: 0.05) {
                        Text("Hold delay")
                    } minimumValueLabel: {
                        Text("0.15s").font(.caption2)
                    } maximumValueLabel: {
                        Text("0.6s").font(.caption2)
                    }
                    .onChange(of: settings.holdThreshold) { _, _ in onSettingsChanged() }

                    Text(
                        "\(settings.holdThreshold, specifier: "%.2f")s — how long to hold before recording starts. Pressing any other key in that window cancels, so typing capitals never triggers Flow."
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Text("Double-tap the same key for hands-free mode.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Section("AI cleanup") {
                Toggle("Clean up my speech with Claude", isOn: $settings.aiCleanupEnabled)
                    .onChange(of: settings.aiCleanupEnabled) { _, _ in onSettingsChanged() }

                Text(
                    "Removes filler words, adds punctuation, and formats lists. Falls back to the raw transcript if it's slow or offline, so it can never block your text."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                SecureField("Anthropic API key", text: $apiKey, prompt: Text("sk-ant-…"))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit(saveKey)
                    .onChange(of: apiKey) { _, _ in saveKey() }
                    .disabled(!settings.aiCleanupEnabled)

                if !KeychainStore.hasAPIKey && settings.aiCleanupEnabled {
                    Label(
                        "Without a key, Flow uses basic local cleanup instead.",
                        systemImage: "info.circle"
                    )
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }
            }

            Section("Vocabulary") {
                Text("Names and jargon Flow should spell correctly.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

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
            }

            Section("General") {
                Toggle("Show icon in the Dock", isOn: $settings.showInDock)
                    .onChange(of: settings.showInDock) { _, _ in onSettingsChanged() }

                Text(
                    "Turn this off to run from the menu bar only. Flow keeps listening either way."
                )
                .font(.caption)
                .foregroundStyle(.secondary)

                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in
                        setLaunchAtLogin(enabled)
                    }

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
            }
        }
        .formStyle(.grouped)
    }

    // MARK: -

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
