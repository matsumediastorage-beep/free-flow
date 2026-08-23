import AVFoundation
import AppKit
import IOKit.hid

/// The three TCC permissions Flow needs, and the deep links to grant them.
///
/// Important context: these grants are tied to the app's code signature *and*
/// its path on disk. An ad-hoc signed build gets a fresh identity on every
/// rebuild, so macOS silently forgets the grant. `scripts/make-signing-cert.sh`
/// creates a stable identity to avoid that; see the README.
enum Permission: String, CaseIterable, Sendable {
    case accessibility
    case inputMonitoring
    case microphone

    var title: String {
        switch self {
        case .accessibility: return "Accessibility"
        case .inputMonitoring: return "Input Monitoring"
        case .microphone: return "Microphone"
        }
    }

    var why: String {
        switch self {
        case .accessibility:
            return "Lets Flow paste text into whatever app you're using."
        case .inputMonitoring:
            return "Lets Flow notice when you hold the Right Shift key."
        case .microphone:
            return "Lets Flow hear you."
        }
    }

    /// Deep link straight to the correct pane in System Settings.
    var settingsURL: URL {
        let anchor: String
        switch self {
        case .accessibility: anchor = "Privacy_Accessibility"
        case .inputMonitoring: anchor = "Privacy_ListenEvent"
        case .microphone: anchor = "Privacy_Microphone"
        }
        return URL(string: "x-apple.systempreferences:com.apple.preference.security?\(anchor)")!
    }
}

@MainActor
enum Permissions {

    /// The literal value of `kAXTrustedCheckOptionPrompt`. Referenced by string
    /// because the imported global is a mutable `var`, which Swift 6 strict
    /// concurrency rejects as shared mutable state.
    private static let axPromptOption = "AXTrustedCheckOptionPrompt" as CFString

    static func isGranted(_ permission: Permission) -> Bool {
        switch permission {
        case .accessibility:
            // Passing prompt:false means "just tell me", no dialog.
            return AXIsProcessTrustedWithOptions([axPromptOption: false] as CFDictionary)
        case .inputMonitoring:
            return IOHIDCheckAccess(kIOHIDRequestTypeListenEvent) == kIOHIDAccessTypeGranted
        case .microphone:
            return AVCaptureDevice.authorizationStatus(for: .audio) == .authorized
        }
    }

    static var missing: [Permission] {
        Permission.allCases.filter { !isGranted($0) }
    }

    static var allGranted: Bool { missing.isEmpty }

    /// Triggers the system prompt where one exists. Accessibility and Input
    /// Monitoring can only *ask*; the user still has to flip the switch in
    /// System Settings, so callers should follow up with `openSettings`.
    static func request(_ permission: Permission) {
        switch permission {
        case .accessibility:
            _ = AXIsProcessTrustedWithOptions([axPromptOption: true] as CFDictionary)
        case .inputMonitoring:
            _ = IOHIDRequestAccess(kIOHIDRequestTypeListenEvent)
        case .microphone:
            requestMicrophone()
        }
    }

    /// AVFoundation invokes this completion handler on its own queue. It has to
    /// live in a `nonisolated` function — a closure written inline here would
    /// inherit `@MainActor`, and Swift 6's executor check traps the process when
    /// TCC calls back from a background thread.
    private nonisolated static func requestMicrophone() {
        AVCaptureDevice.requestAccess(for: .audio) { _ in }
    }

    static func openSettings(for permission: Permission) {
        NSWorkspace.shared.open(permission.settingsURL)
    }
}
