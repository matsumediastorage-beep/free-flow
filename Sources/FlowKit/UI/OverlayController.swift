import AppKit
import SwiftUI

/// Shows and hides the overlay pill in step with the dictation state.
@MainActor
final class OverlayController {

    private let panel: OverlayPanel
    private let controller: DictationController
    private var hideTask: Task<Void, Never>?
    /// False on a normal launch: loading cached weights is quick and silent, so
    /// the pill stays out of the way. True only on a first-run download.
    private let showsModelLoading: Bool

    /// Read once here rather than per-frame; the panel is AppKit, so it can't
    /// pick this up from the SwiftUI environment the way the pill's contents do.
    private var reduceMotion: Bool {
        NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
    }

    init(controller: DictationController, showsModelLoading: Bool = true) {
        self.controller = controller
        self.showsModelLoading = showsModelLoading
        self.panel = OverlayPanel {
            OverlayView(controller: controller)
        }

        controller.onStateChange = { [weak self] state in
            self?.apply(state)
        }
    }

    private func apply(_ state: DictationState) {
        hideTask?.cancel()

        switch state {
        case .idle:
            // Brief delay so a quick idle blip between stages doesn't flicker.
            hideTask = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(120))
                guard !Task.isCancelled else { return }
                self?.panel.dismiss()
            }

        case .preparing where !showsModelLoading:
            panel.dismiss()

        case .starting, .listening, .transcribing, .polishing, .finished, .failed, .preparing:
            let wasVisible = panel.isVisible
            // Resize to fit the current content before showing.
            panel.contentView?.layoutSubtreeIfNeeded()
            if let fitting = panel.contentView?.fittingSize, fitting.width > 0 {
                // Only animate a resize the user can actually see — an
                // already-hidden panel should just be the right size when it
                // arrives.
                panel.resize(to: fitting, animated: wasVisible && !reduceMotion)
            }
            panel.present()
        }
    }
}
