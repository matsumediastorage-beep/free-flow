import Foundation
import Testing

@testable import Flow

/// Drives `HotkeyStateMachine` with a fake clock so hold timing and double-tap
/// windows can be tested exactly, with no sleeping.
@MainActor
private final class Harness {
    let machine = HotkeyStateMachine()
    var events: [HotkeyEvent] = []

    /// Pending hold timers, newest last.
    private var pendingTimers: [() -> Void] = []
    private var clock = Date(timeIntervalSince1970: 1_000_000)

    init() {
        machine.now = { [unowned self] in self.clock }
        machine.scheduleHoldTimer = { [unowned self] _, body in
            self.pendingTimers.append({ MainActor.assumeIsolated(body) })
        }
        machine.onEvent = { [unowned self] in self.events.append($0) }
    }

    func advance(_ seconds: TimeInterval) {
        clock = clock.addingTimeInterval(seconds)
    }

    /// Simulates the 300ms hold elapsing.
    func fireHoldTimer() {
        advance(machine.holdThreshold)
        let timers = pendingTimers
        pendingTimers.removeAll()
        for timer in timers { timer() }
    }

    func send(_ inputs: HotkeyStateMachine.Input...) {
        for input in inputs { machine.receive(input) }
    }
}

// MARK: - The critical case: typing must never trigger dictation

@Test @MainActor
func shiftPlusLetterTypesNormallyAndNeverRecords() {
    let h = Harness()

    // Press Right Shift, then "A" 40ms later — i.e. typing a capital letter.
    h.send(.triggerDown)
    h.advance(0.04)
    h.send(.otherInput)
    h.send(.triggerUp)

    // It armed (mic pre-warm) then cancelled. Crucially, it never recorded.
    #expect(h.events == [.armed, .cancelled])
    #expect(!h.events.contains(.startedRecording))
    #expect(!h.events.contains(.stoppedRecording))
}

@Test @MainActor
func typingAWholeSentenceNeverRecords() {
    let h = Harness()

    // "Hello There" — two shifted capitals plus ordinary letters.
    for _ in 0..<2 {
        h.send(.triggerDown)
        h.advance(0.05)
        h.send(.otherInput)  // the capital
        h.send(.triggerUp)
        for _ in 0..<4 {
            h.advance(0.08)
            h.send(.otherInput)  // lowercase letters
        }
    }

    #expect(!h.events.contains(.startedRecording))
    #expect(!h.events.contains(.stoppedRecording))
}

@Test @MainActor
func holdTimerThatFiresAfterAnInterruptIsIgnored() {
    let h = Harness()

    // Race: the 300ms timer is already scheduled when "A" arrives.
    h.send(.triggerDown)
    h.send(.otherInput)  // cancels
    h.fireHoldTimer()  // stale timer fires anyway

    // The generation check must swallow it.
    #expect(h.events == [.armed, .cancelled])
}

// MARK: - Deliberate holds

@Test @MainActor
func holdingAloneStartsAndStopsRecording() {
    let h = Harness()

    h.send(.triggerDown)
    h.fireHoldTimer()
    h.advance(2.0)  // speaking
    h.send(.triggerUp)

    #expect(h.events == [.armed, .startedRecording, .stoppedRecording])
}

@Test @MainActor
func quickTapDoesNotRecord() {
    let h = Harness()

    h.send(.triggerDown)
    h.advance(0.1)  // released well before the 300ms threshold
    h.send(.triggerUp)

    #expect(h.events == [.armed, .cancelled])
}

@Test @MainActor
func otherKeyDuringRecordingCancels() {
    let h = Harness()

    h.send(.triggerDown)
    h.fireHoldTimer()
    h.send(.otherInput)  // escape hatch mid-recording

    #expect(h.events == [.armed, .startedRecording, .cancelled])
    #expect(!h.machine.isRecording)
}

@Test @MainActor
func aDifferentModifierCancels() {
    let h = Harness()

    // Right Shift held, then Cmd pressed — that's a shortcut, not dictation.
    h.send(.triggerDown)
    h.advance(0.05)
    h.send(.otherInput)

    #expect(h.events == [.armed, .cancelled])
}

// MARK: - Hands-free (double tap)

@Test @MainActor
func doubleTapEntersHandsFree() {
    let h = Harness()

    h.send(.triggerDown)
    h.advance(0.08)
    h.send(.triggerUp)  // tap 1
    h.advance(0.1)  // inside the 400ms window
    h.send(.triggerDown)  // tap 2

    #expect(h.machine.isHandsFree)
    #expect(h.events.contains(.handsFreeChanged(true)))
    #expect(h.events.contains(.startedRecording))
}

@Test @MainActor
func twoSlowTapsDoNotEnterHandsFree() {
    let h = Harness()

    h.send(.triggerDown)
    h.advance(0.08)
    h.send(.triggerUp)
    h.advance(1.0)  // well outside the double-tap window
    h.send(.triggerDown)

    #expect(!h.machine.isHandsFree)
}

@Test @MainActor
func handsFreeSurvivesTypingAndStopsOnNextPress() {
    let h = Harness()

    h.send(.triggerDown)
    h.advance(0.08)
    h.send(.triggerUp)
    h.advance(0.1)
    h.send(.triggerDown)  // hands-free on
    #expect(h.machine.isHandsFree)

    // Releasing the key must NOT stop it, and typing must not cancel it.
    h.send(.triggerUp)
    h.send(.otherInput)
    h.advance(3.0)
    #expect(h.machine.isRecording)

    // Pressing again stops.
    h.send(.triggerDown)
    #expect(!h.machine.isHandsFree)
    #expect(h.events.last == .stoppedRecording)
}

@Test @MainActor
func typingBetweenTapsInvalidatesDoubleTap() {
    let h = Harness()

    h.send(.triggerDown)
    h.advance(0.08)
    h.send(.triggerUp)  // tap 1
    h.send(.otherInput)  // user typed something
    h.advance(0.1)
    h.send(.triggerDown)  // would-be tap 2

    #expect(!h.machine.isHandsFree)
}

@Test @MainActor
func realDictationIsNotADoubleTapCandidate() {
    let h = Harness()

    // A full hold-and-release dictation…
    h.send(.triggerDown)
    h.fireHoldTimer()
    h.send(.triggerUp)
    // …immediately followed by another press must not be read as a double tap.
    h.advance(0.1)
    h.send(.triggerDown)

    #expect(!h.machine.isHandsFree)
}
