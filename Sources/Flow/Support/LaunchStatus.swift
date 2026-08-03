import Foundation

/// A small status file Flow writes on every launch.
///
/// Permissions can only be inspected from inside the real app process — running
/// the binary from a terminal makes macOS attribute TCC to the terminal instead,
/// which reports the wrong answer. So the app reports on itself, and anything
/// else (a script, a support request, you) just reads the file:
///
///     cat ~/Library/Application\ Support/Flow/status.json
struct LaunchStatus: Codable {
    let launchedAt: Date
    let accessibility: Bool
    /// Cross-check via the no-options API. If this disagrees with
    /// `accessibility`, the options-dictionary call is the thing that's wrong.
    let accessibilityBare: Bool
    let inputMonitoring: Bool
    let microphone: Bool
    /// The one that actually matters: did macOS let us create the event tap?
    /// False here with `accessibility: true` means a stale TCC grant — see
    /// scripts/reset-tcc.sh.
    let hotkeyTapActive: Bool
    let hotkey: String
    let speechModelReady: Bool
    /// Which copy of the app is reporting. If two builds exist, this is how you
    /// tell whether the one you granted is the one that's running.
    let appPath: String

    static var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flow", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("status.json")
    }

    func write() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }
}
