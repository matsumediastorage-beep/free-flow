import AVFoundation
import Foundation

/// Captures microphone audio as 16 kHz mono Float32 — the format Parakeet wants.
///
/// Two details matter for how the app *feels*:
///
///  * **Pre-warming.** `AVAudioEngine.start()` costs ~100ms. We start it the
///    moment the trigger key goes down, during the 300ms hold guard, so the mic
///    is already live by the time recording officially begins.
///  * **Pre-roll.** Everything captured during that guard is kept in a small
///    ring buffer and prepended to the recording. Without it, saying "Send the
///    file" the instant you press the key loses the "S".
///
/// The engine only runs while the trigger is held, so macOS's orange mic
/// indicator is an honest signal of when Flow is listening.
final class AudioRecorder: @unchecked Sendable {

    /// Smoothed 0...1 input level, for the overlay waveform. Called on the main queue.
    var onLevel: (@Sendable (Float) -> Void)?

    static let sampleRate: Double = 16_000

    private let engine = AVAudioEngine()
    private let targetFormat = AVAudioFormat(
        commonFormat: .pcmFormatFloat32,
        sampleRate: AudioRecorder.sampleRate,
        channels: 1,
        interleaved: false
    )!

    /// Guards every field below — the tap callback runs on a realtime audio thread.
    private let lock = NSLock()
    private var converter: AVAudioConverter?
    private var captured: [Float] = []
    private var preRoll: [Float] = []
    private var isCapturing = false

    /// Enough to cover the hold guard plus margin.
    private let preRollCapacity = Int(AudioRecorder.sampleRate * 0.6)
    /// Safety valve so a stuck key can't eat all available RAM.
    private let maxSamples = Int(AudioRecorder.sampleRate * 300)  // 5 minutes

    /// True once the engine is live and audio is flowing into the pre-roll.
    var isCapturingAudio: Bool { engine.isRunning }

    // MARK: - Control

    /// Called when the trigger goes down. Starts the engine and begins filling
    /// the pre-roll buffer, but doesn't commit to a recording yet.
    func prewarm() throws {
        lock.lock()
        let alreadyRunning = engine.isRunning
        captured.removeAll(keepingCapacity: true)
        preRoll.removeAll(keepingCapacity: true)
        isCapturing = false
        lock.unlock()

        guard !alreadyRunning else { return }

        let input = engine.inputNode
        let inputFormat = input.outputFormat(forBus: 0)

        // A zero sample rate means no usable input device is present.
        guard inputFormat.sampleRate > 0 else {
            throw AudioError.noInputDevice
        }

        lock.lock()
        converter = AVAudioConverter(from: inputFormat, to: targetFormat)
        lock.unlock()

        input.removeTap(onBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) {
            [weak self] buffer, _ in
            self?.process(buffer)
        }

        engine.prepare()
        try engine.start()
    }

    /// Promotes the pre-roll into a real recording.
    func beginCapture() {
        lock.lock()
        captured = preRoll  // keep the audio from during the hold guard
        preRoll.removeAll(keepingCapacity: true)
        isCapturing = true
        lock.unlock()
    }

    /// Stops and returns everything captured, including the pre-roll.
    func finish() -> [Float] {
        lock.lock()
        let samples = captured
        captured.removeAll(keepingCapacity: true)
        preRoll.removeAll(keepingCapacity: true)
        isCapturing = false
        lock.unlock()

        teardown()
        return samples
    }

    /// Aborts and throws the audio away.
    func cancel() {
        lock.lock()
        captured.removeAll(keepingCapacity: true)
        preRoll.removeAll(keepingCapacity: true)
        isCapturing = false
        lock.unlock()

        teardown()
    }

    private func teardown() {
        guard engine.isRunning else { return }
        engine.inputNode.removeTap(onBus: 0)
        engine.stop()
        lock.lock()
        converter = nil
        lock.unlock()
    }

    // MARK: - Audio thread

    /// Runs on a realtime audio thread: no allocation-heavy work, no main-actor
    /// hops beyond the level callback.
    private func process(_ buffer: AVAudioPCMBuffer) {
        lock.lock()
        guard let converter else {
            lock.unlock()
            return
        }
        lock.unlock()

        let ratio = targetFormat.sampleRate / buffer.format.sampleRate
        let capacity = AVAudioFrameCount(Double(buffer.frameLength) * ratio) + 1024
        guard
            let output = AVAudioPCMBuffer(
                pcmFormat: targetFormat, frameCapacity: capacity)
        else { return }

        var consumed = false
        var error: NSError?
        converter.convert(to: output, error: &error) { _, status in
            if consumed {
                status.pointee = .noDataNow
                return nil
            }
            consumed = true
            status.pointee = .haveData
            return buffer
        }

        guard error == nil, output.frameLength > 0,
            let channel = output.floatChannelData?[0]
        else { return }

        let frames = Int(output.frameLength)
        let samples = UnsafeBufferPointer(start: channel, count: frames)

        // RMS for the waveform, computed before we take the lock.
        var sumOfSquares: Float = 0
        for sample in samples { sumOfSquares += sample * sample }
        let rms = (sumOfSquares / Float(frames)).squareRoot()

        lock.lock()
        if isCapturing {
            if captured.count < maxSamples {
                captured.append(contentsOf: samples)
            }
        } else {
            preRoll.append(contentsOf: samples)
            if preRoll.count > preRollCapacity {
                preRoll.removeFirst(preRoll.count - preRollCapacity)
            }
        }
        lock.unlock()

        if let onLevel {
            // Speech RMS is small; scale into a range that reads well visually.
            let level = min(1, rms * 12)
            DispatchQueue.main.async { onLevel(level) }
        }
    }
}

enum AudioError: LocalizedError {
    case noInputDevice

    var errorDescription: String? {
        switch self {
        case .noInputDevice:
            return "No microphone available."
        }
    }
}
