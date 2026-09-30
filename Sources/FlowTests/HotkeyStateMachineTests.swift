import Foundation

@testable import FlowKit

/// Drives `HotkeyStateMachine` with a fake clock so hold timing and double-tap
/// windows can be tested exactly, with no sleeping.
@MainActor
final class Harness {
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

/// Registers every hotkey test against the suite.
@MainActor
func registerHotkeyTests(_ suite: TestSuite) async {

    // MARK: - The critical case: typing must never trigger dictation

    await suite.test("Shift + letter types normally and never records") {
        let h = Harness()

        // Press the trigger, then "A" 40ms later — i.e. typing a capital letter.
        h.send(.triggerDown)
        h.advance(0.04)
        h.send(.otherInput)
        h.send(.triggerUp)

        // It armed (mic pre-warm) then cancelled. Crucially, it never recorded.
        suite.expectEqual(h.events, [.armed, .cancelled])
        suite.expect(!h.events.contains(.startedRecording))
        suite.expect(!h.events.contains(.stoppedRecording))
    }

    await suite.test("typing a whole sentence never records") {
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

        suite.expect(!h.events.contains(.startedRecording))
        suite.expect(!h.events.contains(.stoppedRecording))
    }

    await suite.test("hold timer that fires after an interrupt is ignored") {
        let h = Harness()

        // Race: the 300ms timer is already scheduled when "A" arrives.
        h.send(.triggerDown)
        h.send(.otherInput)  // cancels
        h.fireHoldTimer()  // stale timer fires anyway

        // The generation check must swallow it.
        suite.expectEqual(h.events, [.armed, .cancelled])
    }

    await suite.test("reapplying the same hotkey leaves a recording active") {
        let monitor = HotkeyMonitor()
        let h = Harness()
        monitor.machine.scheduleHoldTimer = { _, body in body() }
        monitor.onEvent = { h.events.append($0) }
        monitor.machine.receive(.triggerDown)
        suite.expect(monitor.machine.isRecording)
        monitor.hotkey = .rightShift
        suite.expect(monitor.machine.isRecording)
        suite.expect(!h.events.contains(.cancelled))
    }

    await suite.test("changing the hotkey cancels capture and clears hands-free state") {
        let monitor = HotkeyMonitor()
        var events: [HotkeyEvent] = []
        monitor.onEvent = { events.append($0) }
        monitor.machine.scheduleHoldTimer = { _, body in body() }
        monitor.machine.receive(.triggerDown)
        monitor.hotkey = .leftShift
        suite.expect(!monitor.machine.isRecording)
        suite.expect(events.contains(.cancelled))
        suite.expectEqual(events.last, .handsFreeChanged(false))
    }

    // MARK: - Deliberate holds

    await suite.test("holding alone starts and stops recording") {
        let h = Harness()

        h.send(.triggerDown)
        h.fireHoldTimer()
        h.advance(2.0)  // speaking
        h.send(.triggerUp)

        suite.expectEqual(h.events, [.armed, .startedRecording, .stoppedRecording])
    }

    await suite.test("quick tap does not record") {
        let h = Harness()

        h.send(.triggerDown)
        h.advance(0.1)  // released well before the 300ms threshold
        h.send(.triggerUp)

        suite.expectEqual(h.events, [.armed, .cancelled])
    }

    await suite.test("other key during recording cancels") {
        let h = Harness()

        h.send(.triggerDown)
        h.fireHoldTimer()
        h.send(.otherInput)  // escape hatch mid-recording

        suite.expectEqual(h.events, [.armed, .startedRecording, .cancelled])
        suite.expect(!h.machine.isRecording)
    }

    await suite.test("a different modifier cancels") {
        let h = Harness()

        // Trigger held, then Cmd pressed — that's a shortcut, not dictation.
        h.send(.triggerDown)
        h.advance(0.05)
        h.send(.otherInput)

        suite.expectEqual(h.events, [.armed, .cancelled])
    }

    // MARK: - Hands-free (double tap)

    await suite.test("double tap enters hands-free") {
        let h = Harness()

        h.send(.triggerDown)
        h.advance(0.08)
        h.send(.triggerUp)  // tap 1
        h.advance(0.1)  // inside the 400ms window
        h.send(.triggerDown)  // tap 2

        suite.expect(h.machine.isHandsFree)
        suite.expect(h.events.contains(.handsFreeChanged(true)))
        suite.expect(h.events.contains(.startedRecording))
    }

    await suite.test("two slow taps do not enter hands-free") {
        let h = Harness()

        h.send(.triggerDown)
        h.advance(0.08)
        h.send(.triggerUp)
        h.advance(1.0)  // well outside the double-tap window
        h.send(.triggerDown)

        suite.expect(!h.machine.isHandsFree)
    }

    await suite.test("hands-free survives typing and stops on next press") {
        let h = Harness()

        h.send(.triggerDown)
        h.advance(0.08)
        h.send(.triggerUp)
        h.advance(0.1)
        h.send(.triggerDown)  // hands-free on
        suite.expect(h.machine.isHandsFree)

        // Releasing the key must NOT stop it, and typing must not cancel it.
        h.send(.triggerUp)
        h.send(.otherInput)
        h.advance(3.0)
        suite.expect(h.machine.isRecording)

        // Pressing again stops.
        h.send(.triggerDown)
        suite.expect(!h.machine.isHandsFree)
        suite.expectEqual(h.events.last, .stoppedRecording)
    }

    await suite.test("typing between taps invalidates double tap") {
        let h = Harness()

        h.send(.triggerDown)
        h.advance(0.08)
        h.send(.triggerUp)  // tap 1
        h.send(.otherInput)  // user typed something
        h.advance(0.1)
        h.send(.triggerDown)  // would-be tap 2

        suite.expect(!h.machine.isHandsFree)
    }

    await suite.test("real dictation is not a double-tap candidate") {
        let h = Harness()

        // A full hold-and-release dictation…
        h.send(.triggerDown)
        h.fireHoldTimer()
        h.send(.triggerUp)
        // …immediately followed by another press must not be read as a double tap.
        h.advance(0.1)
        h.send(.triggerDown)

        suite.expect(!h.machine.isHandsFree)
    }
}
