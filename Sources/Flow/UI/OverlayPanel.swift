import AppKit
import SwiftUI

/// The floating pill that appears while you dictate.
///
/// Every setting here serves one requirement: it must appear over whatever
/// you're working in *without taking focus*, so your text cursor stays exactly
/// where it was. `.nonactivatingPanel` plus `canBecomeKey == false` is what
/// guarantees that.
final class OverlayPanel: NSPanel {

    init<Content: View>(@ViewBuilder content: () -> Content) {
        super.init(
            contentRect: NSRect(x: 0, y: 0, width: 260, height: 56),
            styleMask: [.nonactivatingPanel, .borderless],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        level = .statusBar  // above normal windows, below system alerts
        collectionBehavior = [
            .canJoinAllSpaces,  // follows you between Spaces
            .fullScreenAuxiliary,  // shows over fullscreen apps
            .stationary,
            .ignoresCycle,  // never appears in Cmd-Tab
        ]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = true
        // Purely informational, so let clicks fall through to the app behind it.
        ignoresMouseEvents = true
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .utilityWindow

        let hosting = NSHostingView(rootView: content())
        hosting.frame = contentRect(forFrameRect: frame)
        contentView = hosting
    }

    // Both must be false or the panel will steal the keyboard.
    override var canBecomeKey: Bool { false }
    override var canBecomeMain: Bool { false }

    /// Positions the panel near the bottom of whichever screen the pointer is on.
    func reposition() {
        let mouse = NSEvent.mouseLocation
        let screen =
            NSScreen.screens.first { NSMouseInRect(mouse, $0.frame, false) }
            ?? NSScreen.main
        guard let screen else { return }

        let visible = screen.visibleFrame
        let size = frame.size
        let origin = NSPoint(
            x: visible.midX - size.width / 2,
            y: visible.minY + 96
        )
        setFrameOrigin(origin)
    }

    func present() {
        reposition()
        orderFrontRegardless()  // show without activating the app
    }

    func dismiss() {
        orderOut(nil)
    }
}
