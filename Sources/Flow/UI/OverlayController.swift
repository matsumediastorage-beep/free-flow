import AppKit
import SwiftUI

/// Shows and hides the overlay pill in step with the dictation state.
@MainActor
final class OverlayController {

    private let panel: OverlayPanel
    private let controller: DictationController
    private var hideTask: Task<Void, Never>?

    init(controller: DictationController) {
        self.controller = controller
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

        case .listening, .transcribing, .finished, .failed, .preparing:
            // Resize to fit the current content before showing.
            panel.contentView?.layoutSubtreeIfNeeded()
            if let fitting = panel.contentView?.fittingSize, fitting.width > 0 {
                panel.setContentSize(fitting)
            }
            panel.present()
        }
    }
}
