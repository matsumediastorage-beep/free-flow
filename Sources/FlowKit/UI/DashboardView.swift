import SwiftUI

/// The dashboard shell.
///
/// A sidebar rather than a tab bar: `TabView` is the iPhone idiom, and on macOS
/// a source list is what every first-party app of this shape uses (Mail, Notes,
/// System Settings). It also gives the sidebar its own vibrancy material, which
/// is most of why a Mac window looks like a Mac window.
struct DashboardView: View {
    @Bindable var history: HistoryStore
    @Bindable var settings: Settings
    let onSettingsChanged: () -> Void

    @State private var selection: Panel = .history
    @State private var missingPermissions = Permissions.missing

    enum Panel: Hashable, CaseIterable {
        case history, settings

        var title: String {
            switch self {
            case .history: return "History"
            case .settings: return "Settings"
            }
        }

        var symbol: String {
            switch self {
            case .history: return "waveform"
            case .settings: return "gearshape"
            }
        }
    }

    var body: some View {
        NavigationSplitView {
            sidebar
                .navigationSplitViewColumnWidth(min: 168, ideal: 188, max: 240)
        } detail: {
            detail
                .navigationSplitViewColumnWidth(min: 440, ideal: 520)
        }
        .navigationSplitViewStyle(.balanced)
        .frame(minWidth: 700, minHeight: 500)
        .onAppear(perform: refresh)
        // Coming back from System Settings is exactly when this changes.
        .onReceive(
            NotificationCenter.default.publisher(
                for: NSApplication.didBecomeActiveNotification)
        ) { _ in
            refresh()
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
        .safeAreaInset(edge: .bottom) { sidebarFooter }
    }

    /// Setup isn't a peer of History and Settings — it's a problem, and it
    /// should look like one until it goes away.
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
        .sheet(isPresented: $openSetup) {
            SetupSheet(missing: missingPermissions, onRefresh: refresh) {
                openSetup = false
            }
        }
    }

    @State private var openSetup = false

    /// A quiet, always-visible reminder of the one thing you need to remember.
    private var sidebarFooter: some View {
        VStack(alignment: .leading, spacing: 2) {
            Divider()
            HStack(spacing: 5) {
                Image(systemName: "hand.point.up.left")
                    .font(.system(size: 10))
                Text("Hold \(settings.hotkey.displayName)")
                    .font(.system(size: 11, weight: .medium))
            }
            .foregroundStyle(.secondary)
            .padding(.horizontal, 14)
            .padding(.top, 6)
            .padding(.bottom, 10)
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detail: some View {
        switch selection {
        case .history:
            HistoryListView(history: history)
                .navigationTitle("History")
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

/// Shown until all three TCC permissions are granted. macOS requires a human to
/// flip these switches — the app can only ask and link.
///
/// A sheet rather than a tab, because it's a task with a finish line: it appears
/// when there's something to do and leaves when there isn't.
struct SetupSheet: View {
    let missing: [Permission]
    let onRefresh: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 7) {
                Image(systemName: "lock.shield")
                    .font(.system(size: 26, weight: .light))
                    .foregroundStyle(.tint)
                    .padding(.bottom, 3)

                Text("Flow needs a few permissions")
                    .font(.system(size: 17, weight: .semibold))

                Text(
                    "macOS requires you to grant these yourself. Flow can open the right page, but you have to flip the switch."
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 24)
            .padding(.top, 26)
            .padding(.bottom, 18)

            VStack(spacing: 8) {
                ForEach(Permission.allCases, id: \.self) { permission in
                    PermissionRow(
                        permission: permission,
                        granted: !missing.contains(permission)
                    )
                }
            }
            .padding(.horizontal, 24)

            Spacer(minLength: 20)

            Divider()
            HStack {
                Text("You may need to quit and reopen Flow after granting.")
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
        .frame(width: 480, height: 440)
    }
}

private struct PermissionRow: View {
    let permission: Permission
    let granted: Bool

    var body: some View {
        HStack(spacing: 12) {
            // A symbol that swaps by *morphing* reads as the same row changing
            // state, which is what actually happened.
            Image(systemName: granted ? "checkmark.circle.fill" : "circle.dashed")
                .font(.system(size: 17))
                .foregroundStyle(granted ? .green : .secondary)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: 20)

            VStack(alignment: .leading, spacing: 1) {
                Text(permission.title)
                    .font(.system(size: 13, weight: .medium))
                Text(permission.why)
                    .font(.system(size: 11))
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
            }
        }
        .padding(.horizontal, 13)
        .padding(.vertical, 11)
        .background {
            RoundedRectangle(cornerRadius: 9, style: .continuous)
                .fill(granted ? AnyShapeStyle(.quinary) : AnyShapeStyle(.quaternary.opacity(0.5)))
        }
        .animation(.snappy(duration: 0.25), value: granted)
    }
}
