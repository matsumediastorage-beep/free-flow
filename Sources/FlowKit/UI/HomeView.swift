import SwiftUI

/// The first thing you see: is it working, how much has it saved you, and what
/// did it just do.
struct HomeView: View {
    let history: HistoryStore
    @Bindable var settings: Settings
    let dictation: DictationController
    let onOpenSettings: () -> Void
    let onOpenHistory: () -> Void

    var body: some View {
        let insights = HistoryInsights(entries: history.entries)
        let cleanup = EffectiveCleanup.resolve(settings.cleanupEngine)

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                hero(cleanup: cleanup)

                if !cleanup.fixesWords {
                    upgradeCard(cleanup: cleanup)
                }

                statsGrid(insights)

                HStack(alignment: .top, spacing: 18) {
                    weekChart(insights)
                    cleanupCard(cleanup: cleanup)
                        .frame(maxWidth: 260)
                }

                recent
            }
            .padding(24)
            .frame(maxWidth: 900, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - Hero

    private func hero(cleanup: EffectiveCleanup) -> some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(Theme.pillBase)
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Theme.violet.opacity(0.55), .clear],
                        center: .topTrailing, startRadius: 10, endRadius: 380))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Theme.indigo.opacity(0.35), .clear],
                        center: .bottomLeading, startRadius: 10, endRadius: 300))
            RoundedRectangle(cornerRadius: 20, style: .continuous)
                .strokeBorder(Theme.orchid.opacity(0.35), lineWidth: 1)

            HStack(alignment: .center, spacing: 20) {
                VStack(alignment: .leading, spacing: 10) {
                    Text(greeting)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(Theme.glow.opacity(0.85))
                    Text("Hold \(settings.hotkey.displayName) and talk.")
                        .font(Theme.display(26))
                        .foregroundStyle(.white)
                    Text("Let go, and clean, corrected text lands wherever your cursor is.")
                        .font(.system(size: 13))
                        .foregroundStyle(.white.opacity(0.7))
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        StatusChip(
                            symbol: dictation.isEngineReady ? "checkmark" : "hourglass",
                            text: dictation.isEngineReady ? "Speech model ready" : "Getting ready",
                            active: dictation.isEngineReady)
                        StatusChip(
                            symbol: "sparkles",
                            text: cleanup.title,
                            active: cleanup.fixesWords)
                    }
                    .padding(.top, 4)
                }
                Spacer(minLength: 0)
                HeroBars()
                    .frame(width: 150, height: 90)
            }
            .padding(24)
        }
        .environment(\.colorScheme, .dark)
        .frame(minHeight: 180)
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        switch hour {
        case 5..<12: return "GOOD MORNING"
        case 12..<18: return "GOOD AFTERNOON"
        default: return "GOOD EVENING"
        }
    }

    // MARK: - Upgrade

    private func upgradeCard(cleanup: EffectiveCleanup) -> some View {
        Card {
            HStack(alignment: .top, spacing: 14) {
                Image(systemName: "wand.and.stars")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(Theme.brandGradient)
                    .frame(width: 28)
                VStack(alignment: .leading, spacing: 4) {
                    Text(
                        cleanup == .off
                            ? "AI cleanup is off"
                            : "Misheard words aren't being fixed yet"
                    )
                    .font(.system(size: 14, weight: .semibold))
                    Text(
                        "Add a Claude API key and Free Flow will fix words the speech model got wrong, drop the ums, and tidy every sentence before it pastes. Apple Intelligence works too, for free, on macOS 26."
                    )
                    .font(.system(size: 12.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Button("Set up", action: onOpenSettings)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)
            }
        }
    }

    // MARK: - Stats

    private func statsGrid(_ insights: HistoryInsights) -> some View {
        LazyVGrid(
            columns: [GridItem(.adaptive(minimum: 150), spacing: 14)],
            spacing: 14
        ) {
            StatTile(
                symbol: "text.word.spacing",
                value: insights.wordsThisWeek.formatted(),
                label: "words this week")
            StatTile(
                symbol: "clock.badge.checkmark",
                value: HistoryInsights.formatDuration(insights.timeSaved),
                label: "saved vs typing")
            StatTile(
                symbol: "speedometer",
                value: insights.speakingWPM > 0 ? "\(insights.speakingWPM)" : "—",
                label: "words per minute")
            StatTile(
                symbol: "flame",
                value: "\(insights.streakDays)",
                label: "day streak")
        }
    }

    private func weekChart(_ insights: HistoryInsights) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                HStack {
                    SectionLabel(text: "Last 7 days")
                    Spacer()
                    Text("\(insights.dictationsThisWeek) dictations")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                WeekBars(days: insights.lastSevenDays)
                    .frame(height: 110)
            }
        }
    }

    private func cleanupCard(cleanup: EffectiveCleanup) -> some View {
        Card {
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "AI cleanup")
                HStack(spacing: 8) {
                    Image(systemName: cleanup.fixesWords ? "sparkles" : "sparkle")
                        .foregroundStyle(Theme.brandGradient)
                    Text(cleanup.title)
                        .font(.system(size: 15, weight: .semibold))
                }
                Text(cleanupBlurb(cleanup))
                    .font(.system(size: 12))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                if cleanup != .off {
                    Text("Style: \(settings.cleanupStyle.title)")
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8)
                        .padding(.vertical, 3)
                        .background(Capsule().fill(Theme.violet.opacity(0.14)))
                        .foregroundStyle(Theme.violet)
                }
                Spacer(minLength: 0)
                Button("Change…", action: onOpenSettings)
                    .buttonStyle(.link)
                    .font(.system(size: 12))
            }
            .frame(minHeight: 124, alignment: .topLeading)
        }
    }

    private func cleanupBlurb(_ cleanup: EffectiveCleanup) -> String {
        switch cleanup {
        case .claude: return "Fixes misheard words using what you've written, then polishes."
        case .apple: return "Free and on-device. Fixes fillers, punctuation and obvious mishears."
        case .basic: return "Only removes ums and adds a period. Add a key for real fixes."
        case .off: return "Pasting exactly what the speech model heard."
        }
    }

    // MARK: - Recent

    @ViewBuilder
    private var recent: some View {
        let entries = Array(history.entries.prefix(4))
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                SectionLabel(text: "Recent")
                Spacer()
                if !history.entries.isEmpty {
                    Button("See all", action: onOpenHistory)
                        .buttonStyle(.link)
                        .font(.system(size: 12))
                }
            }
            if entries.isEmpty {
                Card {
                    HStack(spacing: 12) {
                        Image(systemName: "waveform")
                            .font(.system(size: 20))
                            .foregroundStyle(Theme.brandGradient)
                        Text("Your dictations show up here, with every word the AI fixed highlighted.")
                            .font(.system(size: 12.5))
                            .foregroundStyle(.secondary)
                    }
                }
            } else {
                VStack(spacing: 10) {
                    ForEach(entries) { entry in
                        RecentRow(entry: entry)
                    }
                }
            }
        }
    }
}

// MARK: - Pieces

private struct StatusChip: View {
    let symbol: String
    let text: String
    let active: Bool

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 10, weight: .bold))
            Text(text)
                .font(.system(size: 11.5, weight: .semibold))
        }
        .foregroundStyle(active ? Color.white : Color.white.opacity(0.7))
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
        .background(
            Capsule().fill(active ? AnyShapeStyle(Theme.brandGradient.opacity(0.55)) : AnyShapeStyle(Color.white.opacity(0.1)))
        )
        .overlay(Capsule().strokeBorder(.white.opacity(0.14), lineWidth: 1))
    }
}

private struct StatTile: View {
    let symbol: String
    let value: String
    let label: String

    var body: some View {
        Card(padding: 16) {
            VStack(alignment: .leading, spacing: 10) {
                Image(systemName: symbol)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.violet)
                    .frame(width: 28, height: 28)
                    .background(
                        RoundedRectangle(cornerRadius: 8, style: .continuous)
                            .fill(Theme.violet.opacity(0.12)))
                VStack(alignment: .leading, spacing: 1) {
                    Text(value)
                        .font(Theme.display(24))
                        .monospacedDigit()
                        .contentTransition(.numericText())
                    Text(label)
                        .font(.system(size: 11.5))
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
}

private struct WeekBars: View {
    let days: [(day: Date, words: Int)]

    var body: some View {
        let peak = max(1, days.map { $0.words }.max() ?? 1)
        HStack(alignment: .bottom, spacing: 10) {
            ForEach(Array(days.enumerated()), id: \.offset) { index, item in
                VStack(spacing: 6) {
                    ZStack(alignment: .bottom) {
                        Capsule(style: .continuous)
                            .fill(Color.secondary.opacity(0.14))
                        Capsule(style: .continuous)
                            .fill(Theme.brandGradient)
                            .frame(height: item.words == 0 ? 0 : max(6, 80 * CGFloat(item.words) / CGFloat(peak)))
                            .opacity(index == days.count - 1 ? 1 : 0.75)
                    }
                    .frame(height: 80)
                    .help("\(item.words) words")
                    Text(item.day.formatted(.dateTime.weekday(.narrow)))
                        .font(.system(size: 10.5, weight: .medium))
                        .foregroundStyle(index == days.count - 1 ? Color.primary : Color.secondary)
                }
                .frame(maxWidth: .infinity)
            }
        }
    }
}

/// Decorative bars echoing the icon, gently breathing.
private struct HeroBars: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private static let shape: [CGFloat] = [0.25, 0.45, 0.7, 1.0, 0.7, 0.45, 0.25]

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 24, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: 9) {
                ForEach(Array(Self.shape.enumerated()), id: \.offset) { index, base in
                    let wave = reduceMotion ? 1 : 0.82 + 0.18 * sin(t * 1.6 + Double(index) * 0.7)
                    Capsule(style: .continuous)
                        .fill(Theme.barGradient)
                        .frame(width: 9, height: 86 * base * CGFloat(wave))
                }
            }
            .shadow(color: Theme.violet.opacity(0.9), radius: 12)
        }
        .accessibilityHidden(true)
    }
}

private struct RecentRow: View {
    let entry: DictationEntry
    @State private var showFixes = false

    var body: some View {
        let fixes = WordDiff.changeCount(from: entry.rawText, to: entry.finalText)
        Card(padding: 14) {
            VStack(alignment: .leading, spacing: 8) {
                if showFixes {
                    DiffText(raw: entry.rawText, final: entry.finalText)
                        .font(.system(size: 13))
                        .textSelection(.enabled)
                } else {
                    Text(entry.finalText)
                        .font(.system(size: 13))
                        .lineLimit(3)
                        .textSelection(.enabled)
                }
                HStack(spacing: 8) {
                    Text(entry.createdAt.formatted(.relative(presentation: .named)))
                    if let app = entry.appName {
                        Text("·")
                        Text(app)
                    }
                    Spacer()
                    if fixes > 0 {
                        Button {
                            withAnimation(.snappy(duration: 0.2)) { showFixes.toggle() }
                        } label: {
                            Label(
                                showFixes ? "Hide changes" : "\(fixes) \(fixes == 1 ? "fix" : "fixes")",
                                systemImage: "sparkles")
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(Theme.violet)
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
            }
        }
    }
}
