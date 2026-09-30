import Foundation

/// Which pass cleans up a transcript before it's pasted.
///
/// Three tiers, deliberately: the difference between them is *where the words
/// go*, not just quality. On-device is the default because it costs nothing,
/// needs no account, and keeps every dictation on the machine — the same reasons
/// the speech model runs locally.
enum CleanupEngine: String, CaseIterable, Codable, Sendable {
    /// Paste exactly what was heard.
    case off
    /// Apple's on-device model. Free, private, offline, no key.
    case onDevice
    /// Claude Haiku. Best quality, needs an API key, costs about $0.10/month.
    case claude

    var title: String {
        switch self {
        case .off: return "Off"
        case .onDevice: return "Apple on-device"
        case .claude: return "Claude Haiku"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Paste the raw transcript, exactly as heard."
        case .onDevice:
            return
                "Apple's built-in model. Free, unlimited, works offline, and your words never leave this Mac. Good at fillers and punctuation; catches the obvious misheard words."
        case .claude:
            return
                "Claude Haiku 4.5. The closest thing to Wispr Flow: best at working out which word you actually said, and at turning rambling speech into clean sentences. Needs an Anthropic API key; typically well under a dollar a month."
        }
    }
}

/// How much the AI pass is allowed to change beyond outright mistakes.
enum CleanupStyle: String, CaseIterable, Codable, Sendable {
    /// Fix misheard words, fillers and punctuation. Otherwise word for word.
    case light
    /// All of that, plus smoothing grammar and run-on sentences so it reads
    /// like something you wrote rather than something you said.
    case polished

    var title: String {
        switch self {
        case .light: return "Light"
        case .polished: return "Polished"
        }
    }

    var detail: String {
        switch self {
        case .light:
            return "Fixes misheard words, fillers and punctuation. Otherwise keeps exactly what you said."
        case .polished:
            return "Also smooths grammar and run-on sentences so it reads like you typed it carefully. Same words, same voice."
        }
    }
}

/// What will *actually* clean up the next dictation, given the setting, the
/// key and the Mac. The setting alone lies: "Claude" with no key, or
/// "On-device" with Apple Intelligence switched off, both quietly fall back.
enum EffectiveCleanup: Equatable, Sendable {
    case claude
    case apple
    case basic
    case off

    static func resolve(_ engine: CleanupEngine) -> EffectiveCleanup {
        switch engine {
        case .off:
            return .off
        case .claude where KeychainStore.hasAPIKey:
            return .claude
        case .claude, .onDevice:
            return AppleFormatter.isAvailable ? .apple : .basic
        }
    }

    var title: String {
        switch self {
        case .claude: return "Claude Haiku"
        case .apple: return "Apple on-device"
        case .basic: return "Basic cleanup"
        case .off: return "Off"
        }
    }

    /// True when misheard words actually get fixed.
    var fixesWords: Bool { self == .claude || self == .apple }
}
