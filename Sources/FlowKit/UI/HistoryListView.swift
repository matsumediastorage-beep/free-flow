import AppKit
import SwiftUI

/// Every dictation you've made, newest first, grouped by day.
struct HistoryListView: View {
    @Bindable var history: HistoryStore
    @State private var search = ""
    @State private var justCopied: UUID?

    var body: some View {
        Group {
            if history.entries.isEmpty {
                EmptyState()
            } else if groups.isEmpty {
                ContentUnavailableView.search(text: search)
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10, pinnedViews: []) {
                        ForEach(groups, id: \.title) { group in
                            SectionLabel(text: group.title)
                                .padding(.top, 10)
                                .padding(.leading, 4)
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
                    .padding(.horizontal, 24)
                    .padding(.vertical, 16)
                    .frame(maxWidth: 900)
                    .frame(maxWidth: .infinity)
                }
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

// MARK: - Diff

/// The pasted text with the AI's changes marked: added or corrected words
/// highlighted, dropped words (the ums, the misheard version) struck through.
struct DiffText: View {
    let raw: String
    let final: String

    var body: some View {
        Text(attributed)
    }

    private var attributed: AttributedString {
        var result = AttributedString()
        let pieces = WordDiff.pieces(from: raw, to: final)
        for (index, piece) in pieces.enumerated() {
            if index > 0 { result += AttributedString(" ") }
            switch piece {
            case .same(let word):
                result += AttributedString(word)
            case .added(let word):
                var part = AttributedString(word)
                part[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Theme.violet
                part[AttributeScopes.SwiftUIAttributes.BackgroundColorAttribute.self] =
                    Theme.violet.opacity(0.14)
                result += part
            case .removed(let word):
                var part = AttributedString(word)
                part[AttributeScopes.SwiftUIAttributes.ForegroundColorAttribute.self] = Color.secondary
                part[AttributeScopes.SwiftUIAttributes.StrikethroughStyleAttribute.self] =
                    Text.LineStyle(pattern: .solid)
                result += part
            }
        }
        return result
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
    @State private var showChanges = false

    var body: some View {
        let fixes = WordDiff.changeCount(from: entry.rawText, to: entry.finalText)

        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 7) {
                Group {
                    if showChanges {
                        DiffText(raw: entry.rawText, final: entry.finalText)
                    } else {
                        Text(entry.finalText)
                    }
                }
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
                    if fixes > 0 {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { showChanges.toggle() }
                        } label: {
                            Label(
                                showChanges ? "Hide changes" : "\(fixes) \(fixes == 1 ? "fix" : "fixes")",
                                systemImage: "sparkles")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.violet)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
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
                    tint: isCopied ? Theme.violet : nil,
                    action: onCopy
                )
            }
        }
        .padding(14)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(nsColor: .controlBackgroundColor).opacity(isHovering ? 1 : 0.6))
        }
        .overlay {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .strokeBorder(
                    isHovering ? AnyShapeStyle(Theme.violet.opacity(0.35)) : AnyShapeStyle(Color.primary.opacity(0.06)),
                    lineWidth: 1)
        }
        .contentShape(.rect)
        .onHover { hovering in
            withAnimation(.easeOut(duration: 0.12)) { isHovering = hovering }
        }
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
                .font(.system(size: 11.5))
                .frame(width: 24, height: 24)
                .foregroundStyle(tint ?? .secondary)
                .contentTransition(.symbolEffect(.replace))
        }
        .buttonStyle(.borderless)
        .help(help)
    }
}

private struct EmptyState: View {
    var body: some View {
        VStack(spacing: 12) {
            Spacer()
            BrandMark(size: 52)
            Text("No dictations yet")
                .font(Theme.display(17, weight: .semibold))
            Text("Hold your dictation key anywhere and start talking.")
                .font(.system(size: 12.5))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .frame(maxWidth: .infinity)
    }
}
