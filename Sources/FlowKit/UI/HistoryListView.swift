import AppKit
import SwiftUI

/// Every dictation you've made, newest first, grouped by day.
struct HistoryListView: View {
    @Bindable var history: HistoryStore
    @State private var search = ""
    @State private var justCopied: UUID?

    var body: some View {
        VStack(spacing: 0) {
            StatsHeader(history: history)
            Divider()

            if history.entries.isEmpty {
                EmptyState()
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                List {
                    ForEach(groups, id: \.title) { group in
                        Section(group.title) {
                            ForEach(group.entries) { entry in
                                EntryRow(
                                    entry: entry,
                                    isCopied: justCopied == entry.id,
                                    onCopy: { copy(entry) },
                                    onInsert: { insert(entry) },
                                    onPin: { history.togglePin(entry) },
                                    onDelete: { history.delete(entry) }
                                )
                            }
                        }
                    }
                }
                .listStyle(.inset)
            }
        }
        .searchable(text: $search, placement: .toolbar, prompt: "Search dictations")
    }

    // MARK: -

    private struct DayGroup {
        let title: String
        let entries: [DictationEntry]
    }

    private var filtered: [DictationEntry] {
        let query = search.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return history.entries }
        return history.entries.filter {
            $0.finalText.localizedCaseInsensitiveContains(query)
                || $0.rawText.localizedCaseInsensitiveContains(query)
        }
    }

    /// Pinned entries float to their own section at the top.
    private var groups: [DayGroup] {
        let entries = filtered
        guard !entries.isEmpty else { return [] }

        var result: [DayGroup] = []
        let pinned = entries.filter(\.isPinned)
        if !pinned.isEmpty {
            result.append(DayGroup(title: "Pinned", entries: pinned))
        }

        let rest = entries.filter { !$0.isPinned }
        let calendar = Calendar.current
        let byDay = Dictionary(grouping: rest) {
            calendar.startOfDay(for: $0.createdAt)
        }

        for day in byDay.keys.sorted(by: >) {
            result.append(
                DayGroup(title: Self.dayTitle(day), entries: byDay[day] ?? []))
        }
        return result
    }

    private static func dayTitle(_ date: Date) -> String {
        let calendar = Calendar.current
        if calendar.isDateInToday(date) { return "Today" }
        if calendar.isDateInYesterday(date) { return "Yesterday" }
        return date.formatted(.dateTime.weekday(.wide).month().day())
    }

    private func copy(_ entry: DictationEntry) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(entry.finalText, forType: .string)

        justCopied = entry.id
        Task {
            try? await Task.sleep(for: .milliseconds(1200))
            if justCopied == entry.id { justCopied = nil }
        }
    }

    /// Copies, hides the dashboard, then pastes into whatever was behind it.
    private func insert(_ entry: DictationEntry) {
        NSApp.keyWindow?.orderOut(nil)
        NSApp.hide(nil)
        Task {
            // Give focus time to land back on the previous app.
            try? await Task.sleep(for: .milliseconds(220))
            TextInserter.insert(entry.finalText)
        }
    }
}

// MARK: - Rows

private struct EntryRow: View {
    let entry: DictationEntry
    let isCopied: Bool
    let onCopy: () -> Void
    let onInsert: () -> Void
    let onPin: () -> Void
    let onDelete: () -> Void

    @State private var isHovering = false

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 5) {
                Text(entry.finalText)
                    .font(.system(size: 13))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 8) {
                    Text(entry.createdAt.formatted(date: .omitted, time: .shortened))
                    if let app = entry.appName {
                        Text("·")
                        Text(app)
                    }
                    Text("·")
                    Text("\(entry.wordCount) words")
                    if entry.wasCleanedUp {
                        Image(systemName: "wand.and.stars")
                            .help("Cleaned up by AI. Raw: \(entry.rawText)")
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.tertiary)
            }

            Spacer(minLength: 0)

            HStack(spacing: 2) {
                if entry.isPinned || isHovering {
                    IconButton(
                        systemName: entry.isPinned ? "pin.fill" : "pin",
                        help: entry.isPinned ? "Unpin" : "Pin",
                        action: onPin
                    )
                }
                if isHovering {
                    IconButton(systemName: "text.insert", help: "Paste into last app", action: onInsert)
                    IconButton(systemName: "trash", help: "Delete", action: onDelete)
                }
                IconButton(
                    systemName: isCopied ? "checkmark" : "doc.on.doc",
                    help: "Copy",
                    tint: isCopied ? .green : nil,
                    action: onCopy
                )
            }
        }
        .padding(.vertical, 5)
        .contentShape(.rect)
        .onHover { isHovering = $0 }
        .onTapGesture(perform: onCopy)
    }
}

private struct IconButton: View {
    let systemName: String
    let help: String
    var tint: Color?
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.system(size: 11))
                .frame(width: 22, height: 22)
                .foregroundStyle(tint ?? .secondary)
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

// MARK: - Header

private struct StatsHeader: View {
    let history: HistoryStore

    var body: some View {
        HStack(spacing: 28) {
            Stat(value: "\(history.entries.count)", label: "dictations")
            Stat(value: "\(history.totalWords.formatted())", label: "words")
            Stat(value: Self.duration(history.totalTimeSaved), label: "saved vs typing")
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 14)
    }

    private struct Stat: View {
        let value: String
        let label: String

        var body: some View {
            VStack(alignment: .leading, spacing: 1) {
                Text(value)
                    .font(.system(size: 19, weight: .semibold, design: .rounded))
                    .monospacedDigit()
                Text(label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private static func duration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        let hours = seconds / 3600
        return String(format: "%.1fh", hours)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 8) {
            Spacer()
            Image(systemName: "waveform")
                .font(.system(size: 34))
                .foregroundStyle(.tertiary)
            Text("No dictations yet")
                .font(.system(size: 14, weight: .medium))
            Text("Hold your dictation key anywhere and start talking.")
                .font(.system(size: 12))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
