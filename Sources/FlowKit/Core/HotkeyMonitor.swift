import AppKit
import CoreGraphics
import Foundation

/// Translates raw CoreGraphics events into `HotkeyStateMachine` inputs.
///
/// The tap is `listenOnly` and every callback returns the event untouched, so
/// Shift never stops behaving like Shift. All the actual decision-making lives
/// in `HotkeyStateMachine`.
@MainActor
final class HotkeyMonitor {

    let machine = HotkeyStateMachine()

    var onEvent: ((HotkeyEvent) -> Void)? {
        get { machine.onEvent }
        set { machine.onEvent = newValue }
    }

    var hotkey: Hotkey = .rightShift {
        didSet {
            guard hotkey != oldValue else { return }
            onEvent?(.cancelled)
            machine.reset()
            onEvent?(.handsFreeChanged(false))
        }
    }

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?

    var isRunning: Bool { eventTap != nil }

    /// Returns false if macOS refused the tap, which always means the
    /// Accessibility / Input Monitoring permission isn't granted yet.
    @discardableResult
    func start() -> Bool {
        guard eventTap == nil else { return true }

        let mask: CGEventMask =
            (1 << CGEventType.flagsChanged.rawValue)
            | (1 << CGEventType.keyDown.rawValue)
            | (1 << CGEventType.leftMouseDown.rawValue)
            | (1 << CGEventType.rightMouseDown.rawValue)

        guard
            let tap = CGEvent.tapCreate(
                tap: .cgSessionEventTap,
                place: .headInsertEventTap,
                options: .listenOnly,  // observe only; never swallow or rewrite
                eventsOfInterest: mask,
                callback: { _, type, event, refcon in
                    guard let refcon else { return Unmanaged.passUnretained(event) }
                    let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(refcon)
                        .takeUnretainedValue()
                    // Tap is attached to the main run loop, so this is already
                    // the main thread.
                    MainActor.assumeIsolated {
                        monitor.handle(type: type, event: event)
                    }
                    return Unmanaged.passUnretained(event)
                },
                userInfo: Unmanaged.passUnretained(self).toOpaque()
            )
        else {
            return false
        }

        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)

        eventTap = tap
        runLoopSource = source
        return true
    }

    func stop() {
        if let tap = eventTap {
            CGEvent.tapEnable(tap: tap, enable: false)
        }
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        eventTap = nil
        runLoopSource = nil
        machine.reset()
    }

    private func handle(type: CGEventType, event: CGEvent) {
        switch type {
        case .tapDisabledByTimeout, .tapDisabledByUserInput:
            // macOS can disable a tap under load. Bring it straight back or the
            // hotkey silently dies for the rest of the session.
            onEvent?(.cancelled)
            machine.reset()
            onEvent?(.handsFreeChanged(false))
            if let tap = eventTap {
                CGEvent.tapEnable(tap: tap, enable: true)
            }

        case .flagsChanged:
            let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
            if keyCode == hotkey.keyCode {
                machine.receive(hotkey.isHeld(in: event.flags) ? .triggerDown : .triggerUp)
            } else {
                // A different modifier joined in (e.g. Cmd) — that's a real
                // shortcut, not dictation.
                machine.receive(.otherInput)
            }

        case .keyDown, .leftMouseDown, .rightMouseDown:
            machine.receive(.otherInput)

        default:
            break
        }
    }
}
