import CoreGraphics

/// A modifier key that can act as the push-to-talk trigger.
///
/// Only modifiers are offered, and only *right-hand* ones by default, because a
/// bare letter key would be unusable and left-hand modifiers are the ones people
/// actually use while typing.
enum Hotkey: String, CaseIterable, Codable, Sendable {
    case leftShift
    case rightShift
    case rightOption
    case rightCommand
    case rightControl
    case fn

    var displayName: String {
        switch self {
        case .leftShift: return "Left Shift"
        case .rightShift: return "Right Shift"
        case .rightOption: return "Right Option"
        case .rightCommand: return "Right Command"
        case .rightControl: return "Right Control"
        case .fn: return "Fn (Globe)"
        }
    }

    /// Virtual keycode reported in the `flagsChanged` event.
    var keyCode: Int64 {
        switch self {
        case .leftShift: return 56
        case .rightShift: return 60
        case .rightOption: return 61
        case .rightCommand: return 54
        case .rightControl: return 62
        case .fn: return 63
        }
    }

    /// Device-*dependent* modifier bit from `IOLLEvent.h`.
    ///
    /// This is the crucial detail: `CGEventFlags.maskShift` is set for *either*
    /// shift key, so it can't tell left from right. These lower bits can.
    var deviceMask: UInt64 {
        switch self {
        case .leftShift: return 0x0000_0002  // NX_DEVICELSHIFTKEYMASK
        case .rightShift: return 0x0000_0004  // NX_DEVICERSHIFTKEYMASK
        case .rightOption: return 0x0000_0040  // NX_DEVICERALTKEYMASK
        case .rightCommand: return 0x0000_0010  // NX_DEVICERCMDKEYMASK
        case .rightControl: return 0x0000_2000  // NX_DEVICERCTLKEYMASK
        case .fn: return 0x0080_0000  // NX_SECONDARYFNMASK
        }
    }

    /// True when this specific key is physically down in the given flags.
    func isHeld(in flags: CGEventFlags) -> Bool {
        flags.rawValue & deviceMask != 0
    }

    /// Either Shift doubles as a key people press constantly while typing, so
    /// these need the strictest guard. Left Shift needs it most — it's the one
    /// most touch typists reach for by default.
    var needsTypingGuard: Bool { self == .leftShift || self == .rightShift }
}
