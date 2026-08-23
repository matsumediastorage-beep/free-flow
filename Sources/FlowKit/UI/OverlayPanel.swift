import AppKit
import QuartzCore
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

    /// Fades and lifts the panel into place.
    ///
    /// The pill is a transient thing that appears under your hands mid-sentence,
    /// so it should arrive rather than blink into existence — but it also can't
    /// be slow, because it's competing with the sound of your own voice. ~140ms
    /// with a slight upward drift is the shortest move that still reads as one.
    func present() {
        let wasVisible = isVisible
        reposition()

        guard !wasVisible else {
            orderFrontRegardless()
            return
        }

        alphaValue = 0
        let target = frame
        setFrameOrigin(NSPoint(x: target.origin.x, y: target.origin.y - 8))
        orderFrontRegardless()  // show without activating the app

        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.14
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            animator().alphaValue = 1
            animator().setFrame(target, display: true)
        }
    }

    func dismiss() {
        guard isVisible else { return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.12
            context.timingFunction = CAMediaTimingFunction(name: .easeIn)
            animator().alphaValue = 0
        } completionHandler: { [weak self] in
            guard let self, self.alphaValue < 0.05 else { return }
            self.orderOut(nil)
        }
    }

    /// Grows or shrinks around the centre, so the pill stays put horizontally
    /// while its contents change length.
    func resize(to size: NSSize, animated: Bool) {
        let current = frame
        let target = NSRect(
            x: current.midX - size.width / 2,
            y: current.origin.y,
            width: size.width,
            height: size.height
        )
        guard animated, isVisible else {
            setFrame(target, display: true)
            return
        }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.2
            context.timingFunction = CAMediaTimingFunction(
                controlPoints: 0.22, 1, 0.36, 1)  // a gentle overshoot-free ease
            animator().setFrame(target, display: true)
        }
    }
}
