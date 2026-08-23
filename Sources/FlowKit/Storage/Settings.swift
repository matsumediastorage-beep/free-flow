import Foundation
import Observation

/// User preferences, backed by UserDefaults.
///
/// The API key deliberately lives in the Keychain instead — see `KeychainStore`.
@MainActor
@Observable
final class Settings {

    private let defaults: UserDefaults

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        self.hotkey =
            Hotkey(rawValue: defaults.string(forKey: Keys.hotkey) ?? "") ?? .leftShift
        self.holdThreshold =
            defaults.object(forKey: Keys.holdThreshold) as? Double ?? 0.3
        // Migration: `aiCleanupEnabled` was a Bool before there was more than
        // one engine to choose from. An old `true` means "clean it up", which
        // now resolves to the free on-device pass rather than a paid one.
        if let raw = defaults.string(forKey: Keys.cleanupEngine),
            let engine = CleanupEngine(rawValue: raw)
        {
            self.cleanupEngine = engine
        } else if let legacy = defaults.object(forKey: Keys.aiCleanup) as? Bool {
            self.cleanupEngine = legacy ? .onDevice : .off
        } else {
            self.cleanupEngine = .onDevice
        }
        self.vocabulary = defaults.stringArray(forKey: Keys.vocabulary) ?? []
        self.retentionDays = defaults.object(forKey: Keys.retentionDays) as? Int ?? 0
        self.playSounds = defaults.object(forKey: Keys.playSounds) as? Bool ?? true
        self.showInDock = defaults.object(forKey: Keys.showInDock) as? Bool ?? true
    }

    /// Dock icon + Cmd-Tab, or menu bar only. Menu-bar-only is tidier but makes
    /// the app easy to lose track of, so showing in the Dock is the default.
    var showInDock: Bool {
        didSet { defaults.set(showInDock, forKey: Keys.showInDock) }
    }

    var hotkey: Hotkey {
        didSet { defaults.set(hotkey.rawValue, forKey: Keys.hotkey) }
    }

    /// How long the trigger must be held before recording starts.
    var holdThreshold: Double {
        didSet { defaults.set(holdThreshold, forKey: Keys.holdThreshold) }
    }

    var cleanupEngine: CleanupEngine {
        didSet { defaults.set(cleanupEngine.rawValue, forKey: Keys.cleanupEngine) }
    }

    /// Names and jargon the AI pass should spell correctly.
    var vocabulary: [String] {
        didSet { defaults.set(vocabulary, forKey: Keys.vocabulary) }
    }

    /// Days of history to keep. 0 = forever.
    var retentionDays: Int {
        didSet { defaults.set(retentionDays, forKey: Keys.retentionDays) }
    }

    var playSounds: Bool {
        didSet { defaults.set(playSounds, forKey: Keys.playSounds) }
    }

    private enum Keys {
        static let hotkey = "hotkey"
        static let holdThreshold = "holdThreshold"
        static let aiCleanup = "aiCleanupEnabled"  // legacy, read once for migration
        static let cleanupEngine = "cleanupEngine"
        static let vocabulary = "vocabulary"
        static let retentionDays = "retentionDays"
        static let playSounds = "playSounds"
        static let showInDock = "showInDock"
    }
}
