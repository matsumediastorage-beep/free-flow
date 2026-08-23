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
        case .onDevice: return "On-device (free)"
        case .claude: return "Claude (best)"
        }
    }

    var detail: String {
        switch self {
        case .off:
            return "Paste the raw transcript, exactly as heard."
        case .onDevice:
            return
                "Apple's built-in model. Free and unlimited, works offline, and your words never leave this Mac. Handles fillers, punctuation and spoken corrections well."
        case .claude:
            return
                "Claude Haiku 4.5. Better at restructuring rambling speech and long paragraphs. Needs an Anthropic API key and costs roughly $0.10 a month at normal use."
        }
    }
}
