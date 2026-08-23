import Foundation

/// One completed dictation, as shown in the dashboard history.
struct DictationEntry: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let createdAt: Date
    /// Exactly what the speech model heard, before any AI cleanup.
    let rawText: String
    /// What actually got pasted. Equal to `rawText` when cleanup is off.
    var finalText: String
    let audioDuration: TimeInterval
    /// Which app the text was inserted into, e.g. "Slack".
    let appName: String?
    var isPinned: Bool

    init(
        id: UUID = UUID(),
        createdAt: Date = Date(),
        rawText: String,
        finalText: String,
        audioDuration: TimeInterval,
        appName: String?,
        isPinned: Bool = false
    ) {
        self.id = id
        self.createdAt = createdAt
        self.rawText = rawText
        self.finalText = finalText
        self.audioDuration = audioDuration
        self.appName = appName
        self.isPinned = isPinned
    }

    var wordCount: Int {
        finalText.split(whereSeparator: \.isWhitespace).count
    }

    /// True when the AI cleanup pass actually changed something.
    var wasCleanedUp: Bool {
        rawText != finalText
    }

    /// Roughly how long these words would have taken to type, at 40wpm.
    var typingTimeEquivalent: TimeInterval {
        Double(wordCount) / 40.0 * 60.0
    }

    /// Time saved versus typing it out.
    var timeSaved: TimeInterval {
        max(0, typingTimeEquivalent - audioDuration)
    }
}
