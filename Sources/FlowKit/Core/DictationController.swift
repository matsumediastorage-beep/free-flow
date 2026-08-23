import AppKit
import Foundation
import Observation
import os

enum DictationState: Equatable, Sendable {
    case idle
    /// First-run model download, then the CoreML warm-up.
    case preparing(PreparePhase)
    case listening
    case transcribing
    case finished(String)
    case failed(String)
}

/// Orchestrates one dictation, start to finish:
/// hotkey → mic → Parakeet → cleanup → paste → history.
@MainActor
@Observable
final class DictationController {

    private(set) var state: DictationState = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }
    /// 0...1 mic level, drives the overlay waveform.
    private(set) var level: Float = 0
    private(set) var isHandsFree = false

    /// Lets the overlay show and hide itself without polling.
    var onStateChange: ((DictationState) -> Void)?

    /// Fired once models are loaded and warmed, with how long each phase took.
    var onEngineReady: ((_ loadSeconds: Double, _ warmupSeconds: Double) -> Void)?

    private let settings: Settings
    private let history: HistoryStore
    private let engine: any TranscriptionEngine
    private let recorder = AudioRecorder()
    private let monitor = HotkeyMonitor()
    private let logger = Logger(subsystem: "com.matsumedia.flow", category: "dictation")

    /// Swapped when the user toggles AI cleanup or sets a key.
    var formatter: any TextFormatter

    /// Captured when the trigger is pressed — by paste time it's still the
    /// frontmost app, since our overlay never takes focus.
    private var targetApp: NSRunningApplication?

    /// Debounces opening the mic; see `schedulePrewarm()`.
    private var prewarmTask: Task<Void, Never>?

    /// The in-flight model load. A dictation that lands before the engine is
    /// ready awaits this rather than throwing the recording away.
    private var prepareTask: Task<Void, Error>?

    init(
        settings: Settings,
        history: HistoryStore,
        engine: any TranscriptionEngine,
        formatter: any TextFormatter = LocalFormatter()
    ) {
        self.settings = settings
        self.history = history
        self.engine = engine
        self.formatter = formatter

        recorder.onLevel = { [weak self] value in
            MainActor.assumeIsolated { self?.level = value }
        }
        monitor.onEvent = { [weak self] event in
            self?.handle(event)
        }
    }

    // MARK: - Lifecycle

    /// True once the event tap is live and the hotkey actually works.
    var isListening: Bool { monitor.isRunning }

    /// The trigger key's display name, for UI that shouldn't hardcode it.
    var hotkeyName: String { settings.hotkey.displayName }

    /// Returns false when the event tap was refused, which always means
    /// permissions aren't granted yet.
    @discardableResult
    func start() -> Bool {
        monitor.hotkey = settings.hotkey
        monitor.machine.holdThreshold = settings.holdThreshold
        history.pruneOlderThan(days: settings.retentionDays)
        return monitor.start()
    }

    func stop() {
        monitor.stop()
        recorder.cancel()
    }

    /// Downloads (first run) and loads the speech models.
    func prepareEngine() {
        prepareTask = Task { [weak self] in
            guard let self else { return }
            do {
                self.state = .preparing(.loading(0))
                try await self.engine.prepare { phase in
                    Task { @MainActor [weak self] in
                        self?.state = .preparing(phase)
                    }
                }
                self.state = .idle

                let load = await self.engine.loadSeconds
                let warmup = await self.engine.warmupSeconds
                self.logger.info(
                    "Engine ready — load \(load, format: .fixed(precision: 2))s, warmup \(warmup, format: .fixed(precision: 2))s"
                )
                self.onEngineReady?(load, warmup)
            } catch {
                self.logger.error("Model load failed: \(error.localizedDescription)")
                self.state = .failed("Couldn't load the speech model.")
            }
        }
    }

    /// Re-reads settings that affect the hotkey.
    func applySettings() {
        monitor.hotkey = settings.hotkey
        monitor.machine.holdThreshold = settings.holdThreshold
    }

    // MARK: - Hotkey events

    private func handle(_ event: HotkeyEvent) {
        switch event {
        case .armed:
            targetApp = NSWorkspace.shared.frontmostApplication
            schedulePrewarm()

        case .startedRecording:
            prewarmTask?.cancel()
            // Normally the debounced pre-warm already opened the mic. If it
            // hasn't (slow audio device, engine still starting), open it now
            // rather than recording silence.
            if !recorder.isCapturingAudio {
                do {
                    try recorder.prewarm()
                } catch {
                    logger.error("Mic start failed: \(error.localizedDescription)")
                    state = .failed(error.localizedDescription)
                    return
                }
            }
            recorder.beginCapture()
            level = 0
            state = .listening
            play(.start)

        case .stoppedRecording:
            let samples = recorder.finish()
            state = .transcribing
            play(.stop)
            process(samples)

        case .cancelled:
            prewarmTask?.cancel()
            recorder.cancel()
            level = 0
            if case .listening = state { state = .idle }

        case .handsFreeChanged(let on):
            isHandsFree = on
        }
    }

    // MARK: - Mic pre-warm

    /// Waits a beat before opening the mic.
    ///
    /// The trigger arms on every press, and with Left Shift that means every
    /// capital letter you type. Opening `AVAudioEngine` that often would flicker
    /// macOS's orange mic indicator constantly and churn the audio device for no
    /// reason — a `Shift+A` is over in ~50ms and never becomes a recording.
    ///
    /// Waiting 120ms skips all of those, while still leaving ~180ms of the hold
    /// guard for the engine's ~100ms startup, so the mic is live by the time
    /// recording actually begins.
    private func schedulePrewarm() {
        prewarmTask?.cancel()
        prewarmTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self else { return }
            do {
                try self.recorder.prewarm()
            } catch {
                self.logger.error("Mic prewarm failed: \(error.localizedDescription)")
                self.state = .failed(error.localizedDescription)
            }
        }
    }

    // MARK: - The pipeline

    private func process(_ samples: [Float]) {
        let appName = targetApp?.localizedName
        let vocabulary = settings.vocabulary
        let formatter = self.formatter
        let duration = Double(samples.count) / AudioRecorder.sampleRate

        Task { [weak self] in
            guard let self else { return }
            do {
                // Speaking right after launch shouldn't cost you the recording.
                // The load is normally sub-second, so waiting it out beats
                // failing — the audio is already captured either way.
                if await !self.engine.isReady {
                    self.logger.info("Dictation arrived before the model; waiting for load")
                    try? await self.prepareTask?.value
                }

                let transcript = try await self.engine.transcribe(samples)

                guard !transcript.text.isEmpty else {
                    self.state = .idle
                    return
                }

                let context = FormattingContext(appName: appName, vocabulary: vocabulary)
                let finalText = await formatter.format(transcript.text, context: context)

                TextInserter.insert(finalText)

                self.history.add(
                    DictationEntry(
                        rawText: transcript.text,
                        finalText: finalText,
                        audioDuration: duration,
                        appName: appName
                    ))

                self.state = .finished(finalText)
                self.logger.info(
                    "Transcribed \(transcript.text.count) chars in \(transcript.processingTime, format: .fixed(precision: 3))s"
                )

                // Let the overlay show its confirmation, then go quiet.
                try? await Task.sleep(for: .milliseconds(900))
                if case .finished = self.state { self.state = .idle }

            } catch let error as TranscriptionError {
                // "Too short" is the common accidental-trigger case; not worth
                // shouting about.
                if case .tooShort = error {
                    self.state = .idle
                } else {
                    self.state = .failed(error.localizedDescription)
                    self.clearFailureSoon()
                }
            } catch {
                self.logger.error("Transcription failed: \(error.localizedDescription)")
                self.state = .failed("Transcription failed.")
                self.clearFailureSoon()
            }
        }
    }

    // MARK: - Feedback

    private enum Cue {
        case start, stop

        /// System sounds rather than bundled assets — they're already tuned to
        /// the user's alert volume and feel native.
        var soundName: String {
            switch self {
            case .start: return "Tink"
            case .stop: return "Pop"
            }
        }
    }

    private func play(_ cue: Cue) {
        guard settings.playSounds else { return }
        NSSound(named: cue.soundName)?.play()
    }

    private func clearFailureSoon() {
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard let self, case .failed = self.state else { return }
            self.state = .idle
        }
    }
}
