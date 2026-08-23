import Foundation
import Observation
import os

/// The dictation history, persisted as JSON.
///
/// JSON rather than a database on purpose: even a few thousand dictations is
/// well under a megabyte, and it keeps the app dependency-free. `load`/`save`
/// are the only places that touch disk, so swapping in SQLite later would be a
/// contained change.
@MainActor
@Observable
final class HistoryStore {

    private(set) var entries: [DictationEntry] = []

    private let fileURL: URL
    private let logger = Logger(subsystem: "com.matsumedia.flow", category: "history")
    private var saveTask: Task<Void, Never>?

    init(fileURL: URL? = nil) {
        self.fileURL = fileURL ?? Self.defaultURL()
        load()
    }

    static func defaultURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Flow", isDirectory: true)
        try? FileManager.default.createDirectory(at: base, withIntermediateDirectories: true)
        return base.appendingPathComponent("history.json")
    }

    // MARK: - Mutations

    func add(_ entry: DictationEntry) {
        entries.insert(entry, at: 0)
        scheduleSave()
    }

    func delete(_ entry: DictationEntry) {
        entries.removeAll { $0.id == entry.id }
        scheduleSave()
    }

    func togglePin(_ entry: DictationEntry) {
        guard let index = entries.firstIndex(where: { $0.id == entry.id }) else { return }
        entries[index].isPinned.toggle()
        scheduleSave()
    }

    /// Clears everything except pinned entries.
    func clearUnpinned() {
        entries.removeAll { !$0.isPinned }
        scheduleSave()
    }

    /// Drops unpinned entries older than `days`. Pass 0 to keep forever.
    func pruneOlderThan(days: Int) {
        guard days > 0 else { return }
        let cutoff = Date().addingTimeInterval(-Double(days) * 86_400)
        let before = entries.count
        entries.removeAll { !$0.isPinned && $0.createdAt < cutoff }
        if entries.count != before { scheduleSave() }
    }

    // MARK: - Stats

    var totalWords: Int {
        entries.reduce(0) { $0 + $1.wordCount }
    }

    var totalTimeSaved: TimeInterval {
        entries.reduce(0) { $0 + $1.timeSaved }
    }

    // MARK: - Persistence

    /// Debounced so a burst of dictations doesn't rewrite the file repeatedly.
    private func scheduleSave() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(500))
            guard !Task.isCancelled else { return }
            self?.save()
        }
    }

    func save() {
        let snapshot = entries
        let url = fileURL
        let logger = self.logger
        Task.detached(priority: .utility) {
            do {
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let data = try encoder.encode(snapshot)
                // Atomic: a crash mid-write can't leave a truncated file.
                try data.write(to: url, options: .atomic)
            } catch {
                logger.error("Failed to save history: \(error.localizedDescription)")
            }
        }
    }

    private func load() {
        guard let data = try? Data(contentsOf: fileURL) else { return }
        do {
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            entries = try decoder.decode([DictationEntry].self, from: data)
        } catch {
            logger.error("Failed to load history: \(error.localizedDescription)")
        }
    }
}
