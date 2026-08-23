import SwiftUI

/// Contents of the floating pill. Mirrors `DictationState`.
///
/// Design notes, since this is the one piece of Flow you see every single time:
///
///  * **One shape, not five screens.** Every state renders into the same
///    capsule, and the capsule resizes with a spring rather than cutting. The
///    pill should read as a single object changing its mind, not as a series of
///    different popups.
///  * **Motion carries meaning.** The icon uses `contentTransition(.symbolEffect)`
///    so listening → done is a symbol *morph*; the text cross-fades. Nothing
///    moves decoratively.
///  * **Accessibility is not an afterthought.** Reduce Motion drops the springs
///    and the pulse; Reduce Transparency swaps the material for a solid fill.
///    Both are read from the environment, so they take effect live.
struct OverlayView: View {
    @Bindable var controller: DictationController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 11) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 13)
        .frame(minWidth: 180)
        .background(pill)
        .animation(transition, value: controller.state)
    }

    // MARK: - The pill itself

    /// Layered the way macOS layers a real floating control: a material base, a
    /// hairline that catches "light" from above, an accent wash that only
    /// appears while recording, and a shadow that grounds it.
    private var pill: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(reduceTransparency ? 0 : 1)

            Capsule(style: .continuous)
                .fill(Color(nsColor: .windowBackgroundColor))
                .opacity(reduceTransparency ? 1 : 0)

            // Recording tint. Subtle enough to read as a state, not a warning.
            Capsule(style: .continuous)
                .fill(.tint)
                .opacity(isRecording ? (colorScheme == .dark ? 0.16 : 0.10) : 0)

            Capsule(style: .continuous)
                .strokeBorder(borderGradient, lineWidth: 0.75)
        }
        .compositingGroup()
        .shadow(color: .black.opacity(colorScheme == .dark ? 0.45 : 0.18), radius: 18, y: 7)
        .shadow(color: .black.opacity(0.10), radius: 2, y: 1)
    }

    /// A top-lit hairline — brighter at the top edge, fading toward the bottom.
    /// This is what stops a translucent panel from looking flat.
    private var borderGradient: LinearGradient {
        LinearGradient(
            colors: [
                .white.opacity(colorScheme == .dark ? 0.28 : 0.65),
                .white.opacity(colorScheme == .dark ? 0.06 : 0.22),
            ],
            startPoint: .top,
            endPoint: .bottom
        )
    }

    private var isRecording: Bool {
        if case .listening = controller.state { return true }
        return false
    }

    /// Springs everywhere except when the user has asked for less motion.
    private var transition: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0.08)
    }

    // MARK: - Per-state content

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .listening:
            WaveformView(level: controller.level, reduceMotion: reduceMotion)
            label(controller.isHandsFree ? "Hands-free" : "Listening")

        case .transcribing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.75)
                .frame(width: 16)
            label("Transcribing…")

        case .finished(let text):
            icon("checkmark.circle.fill", tint: .green)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 300, alignment: .leading)
                .transition(.opacity)

        case .failed(let message):
            icon("exclamationmark.triangle.fill", tint: .orange)
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(2)
                .frame(maxWidth: 300, alignment: .leading)

        case .preparing(.loading(let fraction)):
            ProgressView(value: fraction)
                .controlSize(.small)
                .frame(width: 88)
            label("Loading speech model… \(Int(fraction * 100))%")

        case .preparing(.warming):
            // Indeterminate on purpose. CoreML reports no progress here, and a
            // bar pinned at 100% is exactly what made launch feel frozen.
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.75)
                .frame(width: 16)
            label("Warming up…")

        case .idle:
            EmptyView()
        }
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .medium, design: .rounded))
            .foregroundStyle(.secondary)
            .transition(.opacity)
    }

    /// `contentTransition(.symbolEffect(.replace))` makes one symbol morph into
    /// the next instead of popping — the detail that makes this feel built-in.
    private func icon(_ name: String, tint: Color) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(tint)
            .contentTransition(.symbolEffect(.replace))
    }
}

/// Live input-level bars, mirrored around the centre line.
///
/// Growing from the middle rather than up from a baseline is what makes it read
/// as a voice rather than a bar chart, and it stays legible at this size where a
/// real waveform would turn to mush.
struct WaveformView: View {
    let level: Float
    var reduceMotion: Bool = false

    private static let barCount = 16
    private static let maxHeight: CGFloat = 22

    @State private var history: [Float] = Array(repeating: 0.05, count: barCount)

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(history.enumerated()), id: \.offset) { index, value in
                Capsule(style: .continuous)
                    .fill(.tint)
                    // Older samples sit further left and fade, so the eye reads
                    // a direction of travel.
                    .opacity(0.35 + 0.65 * (Double(index) / Double(Self.barCount - 1)))
                    .frame(width: 2.5, height: max(2.5, CGFloat(value) * Self.maxHeight))
            }
        }
        .frame(height: Self.maxHeight)
        .animation(
            reduceMotion ? nil : .spring(response: 0.18, dampingFraction: 0.7),
            value: history
        )
        .onChange(of: level) { _, newValue in
            history.removeFirst()
            // Square-root curve: quiet speech still shows visible movement.
            history.append(max(0.05, sqrt(newValue)))
        }
        .accessibilityHidden(true)
    }
}
