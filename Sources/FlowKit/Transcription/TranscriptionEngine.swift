import Foundation

struct Transcript: Sendable {
    let text: String
    /// Time spent in the model, for the log line. The dictation's *audio*
    /// length is computed from the sample count in `DictationController`,
    /// which is the number that reaches history.
    let processingTime: TimeInterval
}

/// What `prepare` is currently doing.
///
/// Worth distinguishing, because the two phases fail and feel completely
/// differently. Downloading has a real percentage and only happens once;
/// warming has no measurable progress, happens on every launch, and used to
/// leave the UI pinned at 100% looking hung.
enum PreparePhase: Equatable, Sendable {
    /// Fetching weights on first run, then loading them. 0...1.
    case loading(Double)
    /// Running the throwaway inference that makes CoreML compile and specialise
    /// the graph for the Neural Engine.
    case warming
}

/// The speech-to-text backend, behind a protocol so the engine can be swapped
/// (or faked in tests) without touching the rest of the app.
protocol TranscriptionEngine: Actor {

    /// True once models are loaded and `transcribe` will succeed.
    var isReady: Bool { get }

    /// Time spent loading models, and warming them up, on the last `prepare()`.
    var loadSeconds: Double { get }
    var warmupSeconds: Double { get }

    /// Downloads (first run only), loads, and warms the models.
    func prepare(progress: @escaping @Sendable (PreparePhase) -> Void) async throws

    func transcribe(_ samples: [Float]) async throws -> Transcript
}

enum TranscriptionError: LocalizedError {
    case notReady
    case tooShort

    var errorDescription: String? {
        switch self {
        case .notReady: return "The speech model is still loading."
        case .tooShort: return "That was too short to transcribe."
        }
    }
}
