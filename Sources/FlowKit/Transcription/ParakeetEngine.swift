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

    /// How long the last `prepare()` took, split into its two real costs.
    private(set) var loadSeconds: Double = 0
    private(set) var warmupSeconds: Double = 0

    var isReady: Bool { manager != nil }

    func prepare(progress: @escaping @Sendable (PreparePhase) -> Void) async throws {
        guard manager == nil else { return }

        let loadStart = Date()
        let models = try await AsrModels.downloadAndLoad(
            version: .v3,
            progressHandler: { value in
                progress(.loading(value.fractionCompleted))
            }
        )

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)

        self.manager = manager
        self.decoderState = TdtDecoderState.make(
            decoderLayers: await manager.decoderLayerCount)
        loadSeconds = Date().timeIntervalSince(loadStart)

        // Announced separately because it has no percentage and takes seconds.
        // Reporting it as "100%" was why launch looked frozen at the end.
        progress(.warming)
        await warmUp(manager)
    }

    /// Runs one throwaway inference so the user's first real dictation isn't
    /// the one that pays for it.
    ///
    /// CoreML defers most of its work until the first prediction — compiling
    /// the graph and specialising it for the Neural Engine. That first call can
    /// take seconds; every call after it is ~100ms. Burning that cost at launch,
    /// on silence, is the difference between "instant" and "why is it hanging".
    private func warmUp(_ manager: AsrManager) async {
        let warmupStart = Date()
        // Just past `minimumSamples`, so the engine does real work on the
        // shortest input it will ever accept. A longer buffer costs more launch
        // time without specialising anything extra.
        let silence = [Float](repeating: 0, count: Int(AudioRecorder.sampleRate * 0.3))
        var state = TdtDecoderState.make(decoderLayers: await manager.decoderLayerCount)
        _ = try? await manager.transcribe(silence, decoderState: &state)
        warmupSeconds = Date().timeIntervalSince(warmupStart)
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
