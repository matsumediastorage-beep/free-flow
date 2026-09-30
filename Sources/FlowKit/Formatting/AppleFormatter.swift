import Foundation
import os

#if canImport(FoundationModels)
    import FoundationModels
#endif

/// Cleans up a transcript with Apple's on-device model.
///
/// Free, unlimited, private, and works on a plane — the same properties that
/// made Parakeet the right choice for the speech half. There's no API key, no
/// per-word cost, and the text never leaves the machine, which matters more here
/// than anywhere else in the app: this pass sees every word you dictate.
///
/// It's a small model (~3B) next to Claude Haiku, so it's the better default
/// rather than the better result. It handles fillers, punctuation and spoken
/// self-corrections well; Claude is still better at restructuring a rambling
/// paragraph. Both are offered.
///
/// Requires macOS 26 with Apple Intelligence switched on. Everything is behind
/// `canImport` and `@available` so the app still builds and runs on macOS 14.
struct AppleFormatter: TextFormatter {

    private let fallback: any TextFormatter
    private let logger = Logger(subsystem: "com.matsumedia.flow", category: "formatter")

    init(fallback: any TextFormatter = LocalFormatter()) {
        self.fallback = fallback
    }

    // MARK: - Availability

    /// Why the on-device model can't be used, or nil when it can.
    ///
    /// Checked at the point of use rather than cached: Apple Intelligence can be
    /// switched on mid-session, and the model can be mid-download.
    static var unavailableReason: String? {
        #if canImport(FoundationModels)
            guard #available(macOS 26.0, *) else {
                return "On-device cleanup needs macOS 26 or later."
            }
            switch SystemLanguageModel.default.availability {
            case .available:
                return nil
            case .unavailable(.appleIntelligenceNotEnabled):
                return "Apple Intelligence is switched off. Turn it on in System Settings."
            case .unavailable(.modelNotReady):
                return "Apple Intelligence is still downloading its model."
            case .unavailable(.deviceNotEligible):
                return "This Mac doesn't support Apple Intelligence."
            case .unavailable:
                return "The on-device model isn't available right now."
            }
        #else
            return "This build has no on-device model support."
        #endif
    }

    static var isAvailable: Bool { unavailableReason == nil }

    // MARK: - Formatting

    var usesAI: Bool { Self.isAvailable }

    /// Called as recording starts. Asks the system to load the model into
    /// memory now, while you're still talking, instead of after you release.
    /// Measured cleanup took over 2s when the model had been paged out.
    func prepare() async {
        #if canImport(FoundationModels)
            guard #available(macOS 26.0, *), Self.isAvailable else { return }
            let session = LanguageModelSession(instructions: "Reply with one word.")
            session.prewarm()
        #endif
    }

    func format(_ raw: String, context: FormattingContext) async -> String {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return trimmed }

        let started = Date()

        #if canImport(FoundationModels)
            guard #available(macOS 26.0, *), Self.isAvailable else {
                return await fallback.format(trimmed, context: context)
            }

            do {
                let cleaned = try await withBudget(
                    seconds: Self.timeout(forCharacterCount: trimmed.count)
                ) {
                    let session = LanguageModelSession(
                        instructions: CleanupPrompt.onDeviceInstructions(for: context))
                    let response = try await session.respond(
                        to: CleanupPrompt.onDevicePrompt(transcript: trimmed, context: context),
                        options: GenerationOptions(
                            // Deterministic: the same dictation should clean up
                            // the same way every time.
                            sampling: .greedy,
                            // Cleaned text is never much longer than the input.
                            maximumResponseTokens: min(2048, trimmed.count / 2 + 128)
                        )
                    )
                    return response.content
                }

                let result = CleanupPrompt.sanitize(cleaned, raw: trimmed)
                // A small model that ignores its instructions tends to answer
                // the transcript rather than rewrite it, and answers run long.
                guard CleanupPrompt.isPlausible(result, raw: trimmed) else {
                    record(false, "Model returned an unusable response", started)
                    return await fallback.format(trimmed, context: context)
                }

                record(
                    true,
                    result == trimmed
                        ? "Nothing needed changing (on-device)" : "Cleaned on-device",
                    started)
                return result

            } catch {
                logger.error(
                    "On-device cleanup failed, falling back: \(error.localizedDescription)")
                record(false, error.localizedDescription, started)
                return await fallback.format(trimmed, context: context)
            }
        #else
            return await fallback.format(trimmed, context: context)
        #endif
    }

    // MARK: - Latency budget

    /// The on-device model has no network round trip, but it does run on the
    /// Neural Engine alongside the speech model, so long inputs still take real
    /// time. Same shape as the Claude budget, with a lower floor.
    static func timeout(forCharacterCount count: Int) -> TimeInterval {
        min(8.0, 2.0 + Double(count) * 0.006)
    }

    /// Runs one throwaway generation so the first real dictation doesn't pay the
    /// model's cold start — the same trick as `ParakeetEngine.warmUp`, and for
    /// the same reason. Measured at ~3s cold versus well under a second warm.
    static func warmUp() async {
        #if canImport(FoundationModels)
            guard #available(macOS 26.0, *), isAvailable else { return }
            let session = LanguageModelSession(instructions: "Reply with one word.")
            _ = try? await session.respond(
                to: "Say ok.",
                options: GenerationOptions(sampling: .greedy, maximumResponseTokens: 8))
        #endif
    }

    /// Races the work against a deadline, because `respond` has no timeout of
    /// its own and this sits directly in the paste path.
    private func withBudget<T: Sendable>(
        seconds: TimeInterval,
        _ work: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await work() }
            group.addTask {
                try await Task.sleep(for: .seconds(seconds))
                throw CleanupTimeout()
            }
            guard let first = try await group.next() else { throw CleanupTimeout() }
            group.cancelAll()
            return first
        }
    }

    private func record(_ succeeded: Bool, _ detail: String, _ started: Date) {
        CleanupStatus(
            at: Date(),
            succeeded: succeeded,
            detail: detail,
            seconds: Date().timeIntervalSince(started)
        ).write()
    }
}

struct CleanupTimeout: LocalizedError {
    var errorDescription: String? { "On-device cleanup ran out of time." }
}
