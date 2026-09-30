@preconcurrency import CoreML
import FluidAudio
import Foundation
import os

/// On-device speech recognition via Parakeet TDT v3 on the Apple Neural Engine.
///
/// Models are downloaded once (~600MB) into Application Support and cached. The
/// `AsrManager` is loaded once at launch and kept warm — loading it per
/// dictation would add seconds of latency.
actor ParakeetEngine: TranscriptionEngine {

    private var manager: AsrManager?
    private let logger = Logger(subsystem: "com.matsumedia.flow", category: "engine")

    /// Below this, Parakeet has nothing useful to work with and the user almost
    /// certainly triggered by accident.
    private let minimumSamples = Int(AudioRecorder.sampleRate * 0.25)

    /// How long the last `prepare()` took, split into its two real costs.
    private(set) var loadSeconds: Double = 0
    private(set) var warmupSeconds: Double = 0
    /// True when the last load came straight from the on-disk cache via the
    /// parallel fast path, rather than FluidAudio's download-and-load.
    private(set) var usedFastPath = false

    var isReady: Bool { manager != nil }

    func prepare(progress: @escaping @Sendable (PreparePhase) -> Void) async throws {
        guard manager == nil else { return }

        let loadStart = Date()

        // Every launch after the first finds the weights on disk. FluidAudio's
        // loader opens the four CoreML models one after another; opening them
        // side by side lets CoreML overlap the disk reads and the Neural
        // Engine hand-off, which is most of what "Warming up" used to be.
        let models: AsrModels
        if let cached = await Self.loadCachedInParallel(logger: logger) {
            models = cached
            usedFastPath = true
        } else {
            models = try await AsrModels.downloadAndLoad(
                version: .v3,
                progressHandler: { value in
                    progress(.loading(value.fractionCompleted))
                }
            )
            usedFastPath = false
        }

        let manager = AsrManager(config: .default)
        try await manager.loadModels(models)

        loadSeconds = Date().timeIntervalSince(loadStart)

        // Announced separately because it has no percentage and takes seconds.
        progress(.warming)
        await warmUp(manager)
        self.manager = manager
    }

    // MARK: - Fast path

    /// A loaded model plus its file name. `MLModel` isn't declared Sendable,
    /// but it's immutable once loaded and CoreML documents prediction as
    /// thread-safe, so handing it across a task boundary is fine.
    private struct Loaded: @unchecked Sendable {
        let name: String
        let model: MLModel
    }

    /// Loads the cached v3 models concurrently. Returns nil — and the caller
    /// falls back to FluidAudio's own loader — if anything is missing or odd,
    /// so this can only ever make launch faster, never break it.
    private static func loadCachedInParallel(logger: Logger) async -> AsrModels? {
        let names = ModelNames.ASR.self
        let repo = AsrModels.defaultCacheDirectory(for: .v3)
        guard AsrModels.modelsExist(at: repo, version: .v3) else { return nil }

        let fm = FileManager.default
        let files = [
            names.preprocessorFile,
            ParakeetEncoderPrecision.int8.encoderFileName,
            names.decoderFile,
            names.jointV3File,
        ]
        guard
            files.allSatisfy({
                fm.fileExists(atPath: repo.appendingPathComponent($0).path)
            })
        else { return nil }

        let started = Date()
        do {
            let loaded = try await withThrowingTaskGroup(of: Loaded.self) { group in
                for file in files {
                    let url = repo.appendingPathComponent(file)
                    let units: MLComputeUnits =
                        file == names.preprocessorFile ? .cpuOnly : .cpuAndNeuralEngine
                    group.addTask {
                        let model = try await MLModel.load(
                            contentsOf: url, configuration: Self.configuration(units))
                        return Loaded(name: file, model: model)
                    }
                }
                var result: [String: MLModel] = [:]
                for try await item in group { result[item.name] = item.model }
                return result
            }

            guard let preprocessor = loaded[names.preprocessorFile],
                let encoder = loaded[ParakeetEncoderPrecision.int8.encoderFileName],
                let decoder = loaded[names.decoderFile],
                let joint = loaded[names.jointV3File]
            else { return nil }

            let vocabulary = try loadVocabulary(
                at: repo.appendingPathComponent(names.vocabularyFile))

            logger.info(
                "Loaded cached models in parallel in \(Date().timeIntervalSince(started), format: .fixed(precision: 2))s"
            )
            return AsrModels(
                encoder: encoder,
                preprocessor: preprocessor,
                decoder: decoder,
                joint: joint,
                configuration: configuration(.cpuAndNeuralEngine),
                vocabulary: vocabulary,
                version: .v3
            )
        } catch {
            logger.error(
                "Parallel load failed, using the standard loader: \(error.localizedDescription)")
            return nil
        }
    }

    /// Same compute units FluidAudio picks: the preprocessor is all CPU ops,
    /// everything else belongs on the Neural Engine.
    private static func configuration(_ units: MLComputeUnits) -> MLModelConfiguration {
        let config = MLModelConfiguration()
        config.computeUnits = units
        config.allowLowPrecisionAccumulationOnGPU = true
        return config
    }

    /// Parakeet v3 ships its vocabulary as `{"0": "<unk>", "1": "▁t", …}`.
    private static func loadVocabulary(at url: URL) throws -> [Int: String] {
        let data = try Data(contentsOf: url)
        let json = try JSONSerialization.jsonObject(with: data)
        var vocabulary: [Int: String] = [:]
        if let dict = json as? [String: String] {
            for (key, value) in dict {
                if let id = Int(key) { vocabulary[id] = value }
            }
        } else if let array = json as? [String] {
            for (index, token) in array.enumerated() { vocabulary[index] = token }
        }
        guard !vocabulary.isEmpty else { throw TranscriptionError.notReady }
        return vocabulary
    }

    // MARK: - Warm-up

    /// Runs one throwaway inference so the user's first real dictation isn't
    /// the one that pays for it.
    ///
    /// CoreML defers most of its work until the first prediction — compiling
    /// the graph and specialising it for the Neural Engine. That first call can
    /// take seconds; every call after it is ~100ms. Burning that cost at launch,
    /// on silence, is the difference between "instant" and "why is it hanging".
    private func warmUp(_ manager: AsrManager) async {
        let warmupStart = Date()
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

        return Transcript(
            text: result.text.trimmingCharacters(in: .whitespacesAndNewlines),
            processingTime: result.processingTime
        )
    }
}
