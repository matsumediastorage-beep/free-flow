import SwiftUI

/// The dashboard shell: a sidebar of four places, and the one you picked.
///
/// A sidebar rather than tabs, because that's the Mac idiom for an app of this
/// shape (Mail, Notes, System Settings), and it gives the window the native
/// vibrancy that makes it feel like it belongs on the Mac.
struct DashboardView: View {
    @Bindable var history: HistoryStore
    @Bindable var settings: Settings
    let dictation: DictationController
    let onSettingsChanged: () -> Void

    @State private var selection: Panel = .home
    @State private var missingPermissions = Permissions.missing
    @State private var openSetup = false

    enum Panel: Hashable, CaseIterable {
        case home, history, dictionary, settings

        var title: String {
            switch self {
            case .home: return "Home"
            case .history: return "History"
            case .dictionary: return "Dictionary"
            case .settings: return "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .home: return "house"
            case .history: return "clock.arrow.circlepath"
            case .dictionary: return "character.book.closed"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 190, ideal: 210, max: 260)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 520, ideal: 640)
        }
        .navigationSplitViewStyle(.balanced)
        .tint(Theme.violet)
        .frame(minWidth: 780, minHeight: 560)
        .onAppear(perform: refresh)
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refresh()
        }
        .sheet(isPresented: $openSetup) {
            SetupSheet(missing: missingPermissions, onRefresh: refresh) {
                openSetup = false
            }
        }
    }

    // MARK: - Sidebar

    private var sidebar: some View {
        List(selection: $selection) {
            if !missingPermissions.isEmpty {
                Section {
                    setupRow
                }
            }

            Section {
                ForEach(Panel.allCases, id: \.self) { panel in
                    Label(panel.title, systemImage: panel.symbol)
                        .tag(panel)
                }
            }
        }
        .listStyle(.sidebar)
        .safeAreaInset(edge: .top) { sidebarHeader }
        .safeAreaInset(edge: .bottom) { sidebarFooter }
    }

    private var sidebarHeader: some View {
        HStack(spacing: 10) {
            BrandMark(size: 30)
            VStack(alignment: .leading, spacing: 0) {
                Text("Free Flow")
                    .font(Theme.display(15))
                Text(appVersion)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.tertiary)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 16)
        .padding(.top, 6)
        .padding(.bottom, 8)
    }

    private var appVersion: String {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String
        return version.map { "Version \($0)" } ?? "Dictation"
    }

    private var setupRow: some View {
        Button {
            openSetup = true
        } label: {
            HStack(spacing: 6) {
                Label("Finish setup", systemImage: "exclamationmark.triangle.fill")
                    .symbolRenderingMode(.multicolor)
                Spacer(minLength: 0)
                Text("\(missingPermissions.count)")
                    .font(.caption.monospacedDigit().weight(.semibold))
                    .foregroundStyle(.white)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(Capsule().fill(.orange))
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
    }

    /// Always-visible status: is it ready, and what do I press.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 0) {
            Divider()
            HStack(spacing: 8) {
                Circle()
                    .fill(dictation.isEngineReady ? Color.green : Color.orange)
                    .frame(width: 7, height: 7)
                    .shadow(color: (dictation.isEngineReady ? Color.green : Color.orange).opacity(0.6), radius: 3)
                VStack(alignment: .leading, spacing: 1) {
                    Text(dictation.isEngineReady ? "Ready" : "Getting ready…")
                        .font(.system(size: 11.5, weight: .semibold))
                    Text("Hold \(settings.hotkey.displayName) to talk")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .home:
            HomeView(
                history: history,
                settings: settings,
                dictation: dictation,
                onOpenSettings: { selection = .settings },
                onOpenHistory: { selection = .history }
            )
            .navigationTitle("")
        case .history:
            HistoryListView(history: history)
                .navigationTitle("History")
        case .dictionary:
            DictionaryView(settings: settings)
                .navigationTitle("Dictionary")
        case .settings:
            SettingsView(
                settings: settings,
                history: history,
                onSettingsChanged: onSettingsChanged
            )
            .navigationTitle("Settings")
        }
    }

    private func refresh() {
        missingPermissions = Permissions.missing
        if missingPermissions.isEmpty { openSetup = false }
    }
}

// MARK: - Setup

/// Shown until all three TCC permissions are granted. macOS requires a human to
/// flip these switches — the app can only ask and link.
struct SetupSheet: View {
    let missing: [Permission]
    let onRefresh: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 8) {
                BrandMark(size: 40)
                    .padding(.bottom, 6)

                Text("Two minutes of setup")
                    .font(Theme.display(20))

                Text(
                    "macOS makes you grant these yourself. Free Flow opens the right page; you flip the switch."
                )
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 26)
            .padding(.top, 28)
            .padding(.bottom, 20)

            VStack(spacing: 8) {
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRow(
                        permission: permission,
                        granted: !missing.contains(permission)
                    )
                }
            }
            .padding(.horizontal, 26)

            Spacer(minLength: 20)

            Divider()
            HStack {
                Text("You may need to quit and reopen Free Flow after granting.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
                Button("Check again", action: onRefresh)
                Button("Done", action: onDismiss)
                    .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 14)
        }
        .frame(width: 500, height: 470)
        .tint(Theme.violet)
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let granted: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 18))
                .foregroundStyle(granted ? AnyShapeStyle(Theme.brandGradient) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 22)

            VStack(alignment: .leading, spacing: 2) {
                Text(permission.title)
                    .font(.system(size: 13, weight: .semibold))
                Text(permission.why)
                    .font(.system(size: 11.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 8)

            if !granted {
                Button("Open") {
                    Permissions.request(permission)
                    Permissions.openSettings(for: permission)
                }
                .controlSize(.small)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(granted ? AnyShapeStyle(.quinary) : AnyShapeStyle(.quaternary.opacity(0.5)))
        }
        .animation(.snappy(duration: 0.25), value: granted)
    }
}
