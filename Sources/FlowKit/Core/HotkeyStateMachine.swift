import Foundation

enum HotkeyEvent: Equatable, Sendable {
    /// Trigger went down. Pre-warm the mic now so we're live by the time
    /// `startedRecording` fires — AVAudioEngine.start() costs ~100ms.
    case armed
    case startedRecording
    /// Finished normally: transcribe what we captured.
    case stoppedRecording
    /// Aborted before it counted. Throw the audio away.
    case cancelled
    case handsFreeChanged(Bool)
}

/// The push-to-talk decision logic, with no knowledge of CoreGraphics.
///
/// It exists as its own type purely so it can be tested exhaustively — this is
/// the logic that decides whether you just dictated a sentence or typed a
/// capital letter, and getting it wrong makes the app unusable.
///
/// The rules:
///  1. Holding the trigger does nothing for `holdThreshold` (default 300ms).
///  2. Any other input during that window, or during recording, aborts —
///     so `Shift+A` types "A" and never records.
///  3. Two quick taps inside `doubleTapWindow` toggle hands-free mode, where
///     recording continues (and survives typing) until the trigger is pressed
///     again.
@MainActor
final class HotkeyStateMachine {

    enum Input: Equatable, Sendable {
        case triggerDown
        case triggerUp
        /// Any other key or mouse press.
        case otherInput
    }

    var onEvent: ((HotkeyEvent) -> Void)?

    var holdThreshold: TimeInterval = 0.3
    var doubleTapWindow: TimeInterval = 0.4

    /// Injectable so tests can drive time deterministically.
    var now: () -> Date = Date.init
    var scheduleHoldTimer: (TimeInterval, @escaping @MainActor () -> Void) -> Void = {
        delay, body in
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) {
            MainActor.assumeIsolated(body)
        }
    }

    private enum State { case idle, arming, recording }
    private var state: State = .idle
    private(set) var isHandsFree = false

    /// Bumped on every state change so stale hold timers are ignored.
    private var generation = 0
    private var lastQuickTapAt: Date?

    var isRecording: Bool { state == .recording }

    func receive(_ input: Input) {
        switch input {
        case .triggerDown: triggerDown()
        case .triggerUp: triggerUp()
        case .otherInput: otherInput()
        }
    }

    func reset() {
        generation &+= 1
        state = .idle
        isHandsFree = false
        lastQuickTapAt = nil
    }

    // MARK: -

    private func triggerDown() {
        // In hands-free, the trigger is a stop button.
        if isHandsFree {
            setHandsFree(false)
            finish()
            return
        }

        // Second tap of a double-tap?
        if let last = lastQuickTapAt, now().timeIntervalSince(last) < doubleTapWindow {
            lastQuickTapAt = nil
            generation &+= 1
            setHandsFree(true)
            state = .recording
            onEvent?(.armed)
            onEvent?(.startedRecording)
            return
        }

        guard state == .idle else { return }

        state = .arming
        generation &+= 1
        let token = generation
        onEvent?(.armed)

        scheduleHoldTimer(holdThreshold) { [weak self] in
            guard let self, self.generation == token, self.state == .arming else { return }
            self.state = .recording
            self.onEvent?(.startedRecording)
        }
    }

    private func triggerUp() {
        // Hands-free ignores the trigger coming back up.
        guard !isHandsFree else { return }

        switch state {
        case .arming:
            // Released before the threshold — a tap, not a hold. Remember it as
            // a double-tap candidate.
            generation &+= 1
            state = .idle
            lastQuickTapAt = now()
            onEvent?(.cancelled)

        case .recording:
            finish()

        case .idle:
            break
        }
    }

    private func otherInput() {
        // Typing shouldn't kill hands-free mode — that's the point of it.
        guard !isHandsFree else { return }

        lastQuickTapAt = nil

        guard state != .idle else { return }
        generation &+= 1
        state = .idle
        onEvent?(.cancelled)
    }

    private func finish() {
        generation &+= 1
        state = .idle
        lastQuickTapAt = nil
        onEvent?(.stoppedRecording)
    }

    private func setHandsFree(_ on: Bool) {
        guard isHandsFree != on else { return }
        isHandsFree = on
        onEvent?(.handsFreeChanged(on))
    }
}
