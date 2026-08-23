import Foundation

/// The outcome of the most recent AI cleanup attempt.
///
/// Cleanup failures are deliberately silent — pasting the raw transcript beats
/// making you wait or showing an error mid-sentence. But silent failure also
/// means a broken API key looks identical to "the model had nothing to fix",
/// which is exactly the trap this file exists to close. Written on every
/// attempt; surfaced in Settings and readable at:
///
///     cat ~/Library/Application\ Support/Flow/cleanup-status.json
struct CleanupStatus: Codable, Sendable {
    let at: Date
    let succeeded: Bool
    /// Human-readable reason on failure, e.g. "HTTP 401 — invalid API key".
    let detail: String
    /// Round-trip time, so a slow key is distinguishable from a rejected one.
    let seconds: Double

    static var fileURL: URL {
        let base = FileManager.default.urls(
            for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flow", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("cleanup-status.json")
    }

    func write() {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        guard let data = try? encoder.encode(self) else { return }
        try? data.write(to: Self.fileURL, options: .atomic)
    }

    static func read() -> CleanupStatus? {
        guard let data = try? Data(contentsOf: fileURL) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(CleanupStatus.self, from: data)
    }
}
