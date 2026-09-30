import Foundation

@testable import FlowKit

// Top-level code is @MainActor under Swift 6, which is what the UI-facing types
// under test require.
let suite = TestSuite()

print("Hotkey state machine")
await registerHotkeyTests(suite)

print("\nDictation lifecycle")
await registerDictationTests(suite)

print("\nText formatting")
await registerFormattingTests(suite)

if !CommandLine.arguments.contains("--skip-permissions") {
    print("\nPermissions")
    print("  (macOS may show a microphone prompt — that is the point of the first test)")
    await registerPermissionsTests(suite)
}

exit(suite.summarize())
