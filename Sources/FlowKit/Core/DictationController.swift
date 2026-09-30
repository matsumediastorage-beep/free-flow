import AppKit
import Foundation
import Observation
import os

enum DictationState: Equatable, Sendable {
    case idle
    /// First-run model download, then the CoreML warm-up.
    case preparing(PreparePhase)
    case starting
    case listening
    case transcribing
    /// The AI pass is fixing and polishing the transcript.
    case polishing
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
    private(set) var isEngineReady = false

    /// Lets the overlay show and hide itself without polling.
    var onStateChange: ((DictationState) -> Void)?

    /// Fired once models are loaded and warmed, with how long each phase took.
    var onEngineReady: ((_ loadSeconds: Double, _ warmupSeconds: Double) -> Void)?

    private let settings: Settings
    private let history: HistoryStore
    private let engine: any TranscriptionEngine
    private let recorder: any AudioRecording
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
    private var prepareTask: Task<Void, Never>?
    private var preparePhase: PreparePhase?
    private var startTask: Task<Bool, Never>?
    private var processTask: Task<Void, Never>?
    private var feedbackTask: Task<Void, Never>?
    private var session = UUID()
    private var recordingActive = false
    private var processing = false
    private let insertText: @MainActor (String) -> Void
    private let readContext: @Sendable () async -> String?

    /// Text before the cursor, read once per dictation as recording starts —
    /// while the target field is certainly still focused.
    private var contextTask: Task<String?, Never>?

    init(
        settings: Settings,
        history: HistoryStore,
        engine: any TranscriptionEngine,
        formatter: any TextFormatter = LocalFormatter(),
        recorder: any AudioRecording = AudioRecorder(),
        insertText: @escaping @MainActor (String) -> Void = TextInserter.insert,
        readContext: @escaping @Sendable () async -> String? = { await FocusedTextContext.read() }
    ) {
        self.settings = settings
        self.history = history
        self.engine = engine
        self.formatter = formatter
        self.recorder = recorder
        self.insertText = insertText
        self.readContext = readContext

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
        session = UUID()
        prewarmTask?.cancel()
        startTask?.cancel()
        processTask?.cancel()
        feedbackTask?.cancel()
        contextTask?.cancel()
        contextTask = nil
        recordingActive = false
        processing = false
        isHandsFree = false
        recorder.cancel()
        state = .idle
    }

    /// Downloads (first run) and loads the speech models.
    func prepareEngine() {
        guard prepareTask == nil else { return }
        preparePhase = .loading(0)
        state = .preparing(.loading(0))
        prepareTask = Task { [weak self] in
            guard let self else { return }
            do {
                try await self.engine.prepare { phase in
                    Task { @MainActor [weak self] in
                        guard let self, self.preparePhase != nil else { return }
                        self.preparePhase = phase
                        if case .preparing = self.state { self.state = .preparing(phase) }
                    }
                }
                self.preparePhase = nil
                self.isEngineReady = true
                if case .preparing = self.state { self.state = .idle }

                let load = await self.engine.loadSeconds
                let warmup = await self.engine.warmupSeconds
                self.logger.info(
                    "Engine ready — load \(load, format: .fixed(precision: 2))s, warmup \(warmup, format: .fixed(precision: 2))s"
                )
                self.onEngineReady?(load, warmup)
            } catch {
                self.logger.error("Model load failed: \(error.localizedDescription)")
                self.preparePhase = nil
                self.prepareTask = nil  // A later attempt may retry.
                if case .preparing = self.state {
                    self.state = .failed("Couldn't load the speech model.")
                    self.clearFailureSoon()
                }
            }
        }
    }

    /// Re-reads settings that affect the hotkey.
    func applySettings() {
        monitor.hotkey = settings.hotkey
        monitor.machine.holdThreshold = settings.holdThreshold
    }

    // MARK: - Hotkey events

    func handle(_ event: HotkeyEvent) {
        switch event {
        case .armed:
            // Do not let a second gesture overwrite audio or paste out of order.
            guard !processing else {
                monitor.machine.reset()
                isHandsFree = false
                return
            }
            feedbackTask?.cancel()
            session = UUID()
            recordingActive = true
            targetApp = NSWorkspace.shared.frontmostApplication
            schedulePrewarm()

        case .startedRecording:
            guard recordingActive, !processing else { return }
            prewarmTask?.cancel()
            state = .starting
            beginGatheringContext()
            let token = session
            let startedAt = Date()
            startTask = Task { [weak self] in
                guard let self, !Task.isCancelled else { return false }
                do {
                    try await self.recorder.beginCapture()
                    guard !Task.isCancelled, self.session == token else { return false }
                    self.logger.info("Microphone ready in \(Date().timeIntervalSince(startedAt), format: .fixed(precision: 3))s")
                    self.level = 0
                    // A release can arrive while the audio device is opening.
                    if !self.processing {
                        self.state = .listening
                        self.play(.start)
                    }
                    return true
                } catch {
                    guard !Task.isCancelled, self.session == token else { return false }
                    self.recordingActive = false
                    self.monitor.machine.reset()
                    self.isHandsFree = false
                    self.recorder.cancel()
                    self.state = .failed(error.localizedDescription)
                    self.clearFailureSoon()
                    return false
                }
            }

        case .stoppedRecording:
            guard recordingActive, !processing else { return }
            prewarmTask?.cancel()
            recordingActive = false
            processing = true
            state = .transcribing
            play(.stop)
            process()

        case .cancelled:
            guard recordingActive, !processing else { return }
            session = UUID()
            recordingActive = false
            prewarmTask?.cancel()
            startTask?.cancel()
            contextTask?.cancel()
            contextTask = nil
            recorder.cancel()
            level = 0
            restoreIdleState()

        case .handsFreeChanged(let on):
            isHandsFree = on
        }
    }

    /// Starts the two things that can happen while you talk instead of after:
    /// reading the text around the cursor, and opening the connection the AI
    /// pass will use. Both would otherwise add to the wait after release.
    private func beginGatheringContext() {
        let formatter = self.formatter
        if formatter.usesAI {
            Task.detached(priority: .utility) { await formatter.prepare() }
        }
        if formatter.usesAI, settings.useScreenContext {
            let read = readContext
            contextTask = Task.detached(priority: .userInitiated) { await read() }
        } else {
            contextTask = nil
        }
    }

    private func restoreIdleState() {
        state = preparePhase.map { .preparing($0) } ?? .idle
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
        let token = session
        prewarmTask = Task { [weak self] in
            try? await Task.sleep(for: .milliseconds(120))
            guard !Task.isCancelled, let self, self.session == token else { return }
            do {
                try await self.recorder.prewarm()
            } catch {
                self.logger.error("Mic prewarm failed: \(error.localizedDescription)")
                // A deliberate hold retries and reports an error if needed.
            }
        }
    }

    // MARK: - The pipeline

    private func process() {
        let appName = targetApp?.localizedName
        let vocabulary = settings.vocabulary
        let formatter = self.formatter
        let style = settings.cleanupStyle
        let token = session
        let startup = startTask
        let pendingContext = contextTask
        contextTask = nil

        processTask = Task { [weak self] in
            guard let self else { return }
            defer { if self.session == token { self.processing = false } }
            guard await startup?.value == true,
                !Task.isCancelled, self.session == token else { return }
            let samples = await self.recorder.finish()
            let duration = Double(samples.count) / AudioRecorder.sampleRate
            guard !Task.isCancelled, self.session == token else { return }
            do {
                // Speaking right after launch shouldn't cost you the recording.
                // The load is normally sub-second, so waiting it out beats
                // failing — the audio is already captured either way.
                if await !self.engine.isReady {
                    self.logger.info("Dictation arrived before the model; waiting for load")
                    await self.prepareTask?.value
                    try Task.checkCancellation()
                }

                let transcript = try await self.engine.transcribe(samples)
                try Task.checkCancellation()

                guard !transcript.text.isEmpty else {
                    self.state = .idle
                    return
                }

                let preceding = await pendingContext?.value
                try Task.checkCancellation()

                if formatter.usesAI { self.state = .polishing }
                let context = FormattingContext(
                    appName: appName,
                    vocabulary: vocabulary,
                    precedingText: preceding,
                    style: style
                )
                let finalText = await formatter.format(transcript.text, context: context)

                try Task.checkCancellation()
                guard self.session == token else { return }
                // "Hello" then dictating "world" should read "Hello world",
                // not "Helloworld".
                let pasted =
                    FocusedTextContext.needsLeadingSpace(before: preceding, inserting: finalText)
                    ? " " + finalText : finalText
                self.insertText(pasted)

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

                self.feedbackTask = Task { [weak self] in
                    try? await Task.sleep(for: .milliseconds(900))
                    guard !Task.isCancelled, let self, self.session == token else { return }
                    self.restoreIdleState()
                }

            } catch is CancellationError {
                return
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
        feedbackTask?.cancel()
        let token = session
        feedbackTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(2))
            guard !Task.isCancelled, let self, self.session == token, case .failed = self.state else { return }
            self.restoreIdleState()
        }
    }
}
