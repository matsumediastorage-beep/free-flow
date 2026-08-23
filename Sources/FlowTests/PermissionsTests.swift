import Foundation

@testable import FlowKit

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
@MainActor
func registerPermissionsTests(_ suite: TestSuite) async {

    await suite.test("requesting the microphone does not trap on TCC's callback queue") {
        Permissions.request(.microphone)

        // Give TCC time to answer on its own queue. Whether it grants or denies
        // is irrelevant — what matters is that the callback doesn't crash us.
        try? await Task.sleep(for: .milliseconds(600))
    }

    await suite.test("permissions report status without crashing") {
        // Each of these hits a different system API; none should trap.
        for permission in Permission.allCases {
            _ = Permissions.isGranted(permission)
            suite.expect(!permission.title.isEmpty)
            suite.expectEqual(permission.settingsURL.scheme, "x-apple.systempreferences")
        }
        _ = Permissions.missing
    }
}
