import Foundation

struct FormattingContext: Sendable {
    /// The app the text is headed into, e.g. "Slack" — lets the AI pass match
    /// register (casual in chat, formal in Mail).
    let appName: String?
    /// Names and jargon that should be spelled correctly.
    let vocabulary: [String]
}

/// Turns a raw transcript into what actually gets pasted.
protocol TextFormatter: Sendable {
    func format(_ raw: String, context: FormattingContext) async -> String
}

/// Rule-based cleanup with no network call. Used when AI cleanup is disabled or
/// no API key is configured, and as the fallback when the API call fails.
///
/// Deliberately conservative: it only fixes things that are unambiguous, because
/// mangling someone's words is worse than leaving a stray "um" in.
struct LocalFormatter: TextFormatter {

    /// Only removed when they stand completely alone as a word — "um" is always
    /// filler, but "like" and "so" carry meaning, so they're left alone.
    private static let fillers: Set<String> = ["um", "uh", "erm", "uhh", "umm", "hmm"]

    func format(_ raw: String, context: FormattingContext) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let kept = trimmed
            .split(separator: " ", omittingEmptySubsequences: true)
            .filter { word in
                let bare = word.lowercased().trimmingCharacters(
                    in: CharacterSet.alphanumerics.inverted)
                return !Self.fillers.contains(bare)
            }

        var result = kept.joined(separator: " ")
        guard !result.isEmpty else { return trimmed }

        result = result.prefix(1).uppercased() + result.dropFirst()

        if let last = result.last, !".!?,:;".contains(last) {
            result += "."
        }
        return result
    }
}

/// Pastes the transcript exactly as heard.
struct PassthroughFormatter: TextFormatter {
    func format(_ raw: String, context: FormattingContext) async -> String {
        raw.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
