import SwiftUI

struct DashboardView: View {
    @Bindable var history: HistoryStore
    @Bindable var settings: Settings
    let onSettingsChanged: () -> Void

    @State private var selection: Tab = .history
    @State private var missingPermissions = Permissions.missing

    enum Tab: Hashable { case history, settings, setup }

    var body: some View {
        TabView(selection: $selection) {
            HistoryListView(history: history)
                .tabItem { Label("History", systemImage: "clock.arrow.circlepath") }
                .tag(Tab.history)

            SettingsView(
                settings: settings,
                history: history,
                onSettingsChanged: onSettingsChanged
            )
            .tabItem { Label("Settings", systemImage: "gearshape") }
            .tag(Tab.settings)

            if !missingPermissions.isEmpty {
                SetupView(missing: missingPermissions, onRefresh: refresh)
                    .tabItem { Label("Setup", systemImage: "exclamationmark.triangle") }
                    .tag(Tab.setup)
            }
        }
        .frame(minWidth: 620, minHeight: 480)
        .onAppear {
            refresh()
            // Land on Setup if the app can't actually work yet.
            if !missingPermissions.isEmpty { selection = .setup }
        }
    }

    private func refresh() {
        missingPermissions = Permissions.missing
    }
}

/// Shown until all three TCC permissions are granted. macOS requires a human to
/// flip these switches — the app can only ask and link.
struct SetupView: View {
    let missing: [Permission]
    let onRefresh: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Flow needs a few permissions")
                    .font(.system(size: 16, weight: .semibold))
                Text(
                    "macOS requires you to grant these yourself in System Settings. Flow can open the right page, but you have to flip the switch."
                )
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            }

            ForEach(Permission.allCases, id: \.self) { permission in
                let granted = !missing.contains(permission)
                HStack(spacing: 12) {
                    Image(systemName: granted ? "checkmark.circle.fill" : "circle")
                        .foregroundStyle(granted ? .green : .secondary)
                        .font(.system(size: 16))

                    VStack(alignment: .leading, spacing: 2) {
                        Text(permission.title).font(.system(size: 13, weight: .medium))
                        Text(permission.why)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if !granted {
                        Button("Open Settings") {
                            Permissions.request(permission)
                            Permissions.openSettings(for: permission)
                        }
                    }
                }
                .padding(12)
                .background(RoundedRectangle(cornerRadius: 8).fill(.quaternary.opacity(0.4)))
            }

            HStack {
                Button("Check again", action: onRefresh)
                Spacer()
                Text("You may need to quit and reopen Flow after granting.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }

            Spacer()
        }
        .padding(24)
    }
}
