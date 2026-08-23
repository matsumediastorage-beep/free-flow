import AppKit
import FlowKit

/// Entry point. We drive `NSApplication` manually rather than using the SwiftUI
/// `App` lifecycle because Flow is an accessory (menu-bar) app that owns a
/// non-activating overlay panel — both of which are easier to control from AppKit.
///
/// Everything real lives in `FlowKit`; this target is only the shim that starts
/// it, so the app's logic can be linked into a test runner too.
@main
@MainActor
enum FlowMain {
    // NSApplication holds its delegate weakly, so we need a strong reference here.
    private static let delegate = AppDelegate()

    static func main() {
        let app = NSApplication.shared
        app.delegate = delegate
        // The real policy is applied from the user's setting in
        // applicationDidFinishLaunching; .regular here avoids a launch flicker
        // for the default (Dock-visible) case.
        app.setActivationPolicy(.regular)
        app.run()
    }
}
