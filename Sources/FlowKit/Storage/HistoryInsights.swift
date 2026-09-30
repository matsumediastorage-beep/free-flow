import Foundation

/// Word-level comparison of what was heard against what was pasted, so the
/// dashboard can show exactly what the AI pass fixed.
enum WordDiff {

    enum Piece: Equatable, Sendable {
        case same(String)
        case added(String)
        case removed(String)
    }

    /// Longest-common-subsequence over words, compared loosely (case and
    /// punctuation ignored) so "hello," → "Hello." doesn't count as a fix.
    static func pieces(from raw: String, to final: String) -> [Piece] {
        let a = raw.split(whereSeparator: \.isWhitespace).map(String.init)
        let b = final.split(whereSeparator: \.isWhitespace).map(String.init)
        guard !a.isEmpty || !b.isEmpty else { return [] }
        // Keep it cheap on very long dictations.
        guard a.count * b.count <= 250_000 else { return b.map { .same($0) } }

        let ka = a.map(key), kb = b.map(key)
        var table = Array(repeating: Array(repeating: 0, count: b.count + 1), count: a.count + 1)
        for i in stride(from: a.count - 1, through: 0, by: -1) {
            for j in stride(from: b.count - 1, through: 0, by: -1) {
                table[i][j] =
                    ka[i] == kb[j] ? table[i + 1][j + 1] + 1 : max(table[i + 1][j], table[i][j + 1])
            }
        }

        var result: [Piece] = []
        var i = 0, j = 0
        while i < a.count, j < b.count {
            if ka[i] == kb[j] {
                result.append(.same(b[j])); i += 1; j += 1
            } else if table[i + 1][j] >= table[i][j + 1] {
                result.append(.removed(a[i])); i += 1
            } else {
                result.append(.added(b[j])); j += 1
            }
        }
        while i < a.count { result.append(.removed(a[i])); i += 1 }
        while j < b.count { result.append(.added(b[j])); j += 1 }
        return result
    }

    /// How many words the AI pass changed, added or removed.
    static func changeCount(from raw: String, to final: String) -> Int {
        let pieces = pieces(from: raw, to: final)
        let added = pieces.filter { if case .added = $0 { return true } else { return false } }.count
        let removed = pieces.filter { if case .removed = $0 { return true } else { return false } }.count
        return max(added, removed)
    }

    private static func key(_ word: String) -> String {
        word.lowercased().trimmingCharacters(in: .punctuationCharacters)
    }
}

/// The numbers on the Home screen.
struct HistoryInsights {
    let wordsThisWeek: Int
    let dictationsThisWeek: Int
    let timeSaved: TimeInterval
    /// Words per minute of actual speaking, across everything.
    let speakingWPM: Int
    /// Consecutive days with at least one dictation, ending today or yesterday.
    let streakDays: Int
    let totalWords: Int
    /// Words per day for the last seven days, oldest first.
    let lastSevenDays: [(day: Date, words: Int)]

    init(entries: [DictationEntry], now: Date = Date(), calendar: Calendar = .current) {
        let weekAgo = calendar.date(byAdding: .day, value: -7, to: now) ?? now
        let week = entries.filter { $0.createdAt >= weekAgo }
        wordsThisWeek = week.reduce(0) { $0 + $1.wordCount }
        dictationsThisWeek = week.count
        timeSaved = entries.reduce(0) { $0 + $1.timeSaved }
        totalWords = entries.reduce(0) { $0 + $1.wordCount }

        let spoken = entries.reduce(0.0) { $0 + $1.audioDuration }
        speakingWPM = spoken > 5 ? Int(Double(totalWords) / (spoken / 60)) : 0

        let days = Set(entries.map { calendar.startOfDay(for: $0.createdAt) })
        var streak = 0
        var cursor = calendar.startOfDay(for: now)
        if !days.contains(cursor) {
            cursor = calendar.date(byAdding: .day, value: -1, to: cursor) ?? cursor
        }
        while days.contains(cursor) {
            streak += 1
            guard let previous = calendar.date(byAdding: .day, value: -1, to: cursor) else { break }
            cursor = previous
        }
        streakDays = streak

        let today = calendar.startOfDay(for: now)
        var buckets: [(day: Date, words: Int)] = []
        for offset in stride(from: 6, through: 0, by: -1) {
            guard let day = calendar.date(byAdding: .day, value: -offset, to: today) else { continue }
            let words = entries
                .filter { calendar.isDate($0.createdAt, inSameDayAs: day) }
                .reduce(0) { $0 + $1.wordCount }
            buckets.append((day, words))
        }
        lastSevenDays = buckets
    }

    static func formatDuration(_ seconds: TimeInterval) -> String {
        if seconds < 60 { return "\(Int(seconds))s" }
        if seconds < 3600 { return "\(Int(seconds / 60))m" }
        return String(format: "%.1fh", seconds / 3600)
    }
}
