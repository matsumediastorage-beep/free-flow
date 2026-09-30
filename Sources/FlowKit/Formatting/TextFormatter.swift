import Foundation

struct FormattingContext: Sendable {
    /// The app the text is headed into, e.g. "Slack" — lets the AI pass match
    /// register (casual in chat, formal in Mail).
    let appName: String?
    /// Names and jargon that should be spelled correctly.
    let vocabulary: [String]
    /// Whatever was already typed before the cursor, read through
    /// Accessibility. It's the single best clue for fixing a misheard word:
    /// "send it to Blaire" is obviously "Blair" when the email above starts
    /// "Hi Blair,". Nil when the field can't be read, or when it's a password.
    let precedingText: String?
    /// How far the AI pass may go beyond fixing mistakes.
    let style: CleanupStyle

    init(
        appName: String?,
        vocabulary: [String],
        precedingText: String? = nil,
        style: CleanupStyle = .polished
    ) {
        self.appName = appName
        self.vocabulary = vocabulary
        self.precedingText = precedingText
        self.style = style
    }
}

/// Turns a raw transcript into what actually gets pasted.
protocol TextFormatter: Sendable {
    func format(_ raw: String, context: FormattingContext) async -> String

    /// True when formatting involves a model and can take a noticeable moment,
    /// so the overlay should say so instead of looking stuck.
    var usesAI: Bool { get }

    /// Called the moment recording starts, while the user is still talking.
    /// A formatter that talks to a server opens its connection here, so the
    /// TLS handshake is already done by the time there's text to send.
    func prepare() async
}

extension TextFormatter {
    var usesAI: Bool { false }
    func prepare() async {}
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
