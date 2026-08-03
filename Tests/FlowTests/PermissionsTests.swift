import Foundation
import Testing

@testable import Flow

/// Regression test for a crash that killed the app in the field.
///
/// `AVCaptureDevice.requestAccess` invokes its completion handler on an
/// arbitrary background queue. Because `Permissions` is `@MainActor`, a closure
/// written inline there inherited main-actor isolation, and Swift 6's runtime
/// executor check trapped the process (`EXC_BREAKPOINT` in
/// `swift_task_isCurrentExecutorImpl`) the moment TCC called back.
///
/// The fix routes the call through a `nonisolated` helper. This test exercises
/// the same path: if the isolation regression returns, TCC's callback traps and
/// the test process dies rather than failing cleanly — which is still a loud,
/// unmissable signal.
@Test @MainActor
func requestingMicrophoneDoesNotTrapOnTheCallbackQueue() async {
    Permissions.request(.microphone)

    // Give TCC time to answer on its own queue. Whether it grants or denies is
    // irrelevant — what matters is that the callback doesn't crash us.
    try? await Task.sleep(for: .milliseconds(600))
}

@Test @MainActor
func permissionsReportStatusWithoutCrashing() {
    // Each of these hits a different system API; none should trap.
    for permission in Permission.allCases {
        _ = Permissions.isGranted(permission)
        #expect(!permission.title.isEmpty)
        #expect(permission.settingsURL.scheme == "x-apple.systempreferences")
    }
    _ = Permissions.missing
}
