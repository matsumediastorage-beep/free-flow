import Foundation

struct Transcript: Sendable {
    let text: String
    let confidence: Float
    /// Length of the audio, not the time spent transcribing.
    let audioDuration: TimeInterval
    let processingTime: TimeInterval
}

/// Abstracts the speech recognizer so a cloud backend can be dropped in later
/// without touching the rest of the app.
protocol TranscriptionEngine: Actor {
    /// True once models are loaded and `transcribe` will succeed.
    var isReady: Bool { get }

    /// Downloads (first run only) and loads models.
    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws

    /// - Parameter samples: 16 kHz mono Float32.
    func transcribe(_ samples: [Float]) async throws -> Transcript
}

enum TranscriptionError: LocalizedError {
    case notReady
    case tooShort

    var errorDescription: String? {
        switch self {
        case .notReady:
            return "Speech model is still loading."
        case .tooShort:
            return "That was too short to transcribe."
        }
    }
}
