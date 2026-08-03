import FluidAudio
import Foundation

/// On-device speech recognition via Parakeet TDT v3 on the Apple Neural Engine.
///
/// Models are downloaded once (~600MB) into Application Support and cached. The
/// `AsrManager` is loaded once at launch and kept warm — loading it per
/// dictation would add seconds of latency.
actor ParakeetEngine: TranscriptionEngine {

    private var manager: AsrManager?
    private var decoderState: TdtDecoderState?

    /// Below this, Parakeet has nothing useful to work with and the user almost
    /// certainly triggered by accident.
    private let minimumSamples = Int(AudioRecorder.sampleRate * 0.25)

    var isReady: Bool { manager != nil }

    func prepare(progress: @escaping @Sendable (Double) -> Void) async throws {
        guard manager == nil else { return }

        let models = try await AsrModels.downloadAndLoad(
            version: .v3,
            progressHandler: { value in
                progress(value.fractionCompleted)
            }
        )

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)

        self.manager = manager
        self.decoderState = TdtDecoderState.make(
            decoderLayers: await manager.decoderLayerCount)
    }

    func transcribe(_ samples: [Float]) async throws -> Transcript {
        guard let manager else { throw TranscriptionError.notReady }
        guard samples.count >= minimumSamples else { throw TranscriptionError.tooShort }

        // Each dictation is an independent utterance, so the decoder starts
        // fresh — carrying state over would leak context between them.
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        let result = try await manager.transcribe(samples, decoderState: &state)
        self.decoderState = state

        return Transcript(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            confidence: result.confidence,
            audioDuration: result.duration,
            processingTime: result.processingTime
        )
    }
}
