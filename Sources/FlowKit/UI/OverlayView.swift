import SwiftUI

/// Contents of the floating pill. Mirrors `DictationState`.
///
/// Design notes, since this is the one piece of Flow you see every time:
///
///  * **Small and dark, always.** It's the icon come to life: a near-black
///    glass capsule with violet light in it. Dark reads over any window, light
///    or dark mode, and small means it never covers what you're writing.
///  * **One object changing its mind.** Every state renders into the same
///    capsule and it resizes with a spring, so listening → polishing → done
///    reads as one thing progressing, not a series of popups.
///  * **The waveform is the status.** While you talk the bars follow your voice;
///    while Flow works they ripple on their own. You can tell what's happening
///    without reading a word.
///  * **Accessibility.** Reduce Motion drops the ripples and springs; Reduce
///    Transparency makes the capsule solid.
struct OverlayView: View {
    @Bindable var controller: DictationController

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.accessibilityReduceTransparency) private var reduceTransparency

    var body: some View {
        HStack(spacing: 10) {
            content
        }
        .padding(.leading, 14)
        .padding(.trailing, 16)
        .padding(.vertical, 10)
        .frame(minHeight: 40)
        .background(pill)
        .environment(\.colorScheme, .dark)
        .animation(transition, value: controller.state)
    }

    // MARK: - The pill

    private var pill: some View {
        ZStack {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .opacity(reduceTransparency ? 0 : 1)
            Capsule(style: .continuous)
                .fill(Theme.pillBase.opacity(reduceTransparency ? 1 : 0.82))

            // A violet wash from below while Flow is doing something, strongest
            // while it's listening.
            Capsule(style: .continuous)
                .fill(
                    RadialGradient(
                        colors: [Theme.violet.opacity(0.45), .clear],
                        center: .bottom, startRadius: 2, endRadius: 90)
                )
                .opacity(glowAmount)

            Capsule(style: .continuous)
                .strokeBorder(
                    LinearGradient(
                        colors: [
                            Theme.orchid.opacity(0.55 * max(glowAmount, 0.35)),
                            .white.opacity(0.08),
                        ],
                        startPoint: .top, endPoint: .bottom),
                    lineWidth: 1
                )
        }
        .compositingGroup()
        .shadow(color: Theme.violet.opacity(0.35 * glowAmount), radius: 16)
        .shadow(color: .black.opacity(0.35), radius: 12, y: 6)
    }

    private var glowAmount: Double {
        switch controller.state {
        case .listening: return 1
        case .starting, .transcribing, .polishing: return 0.6
        case .finished: return 0.35
        default: return 0
        }
    }

    private var transition: Animation {
        reduceMotion ? .easeOut(duration: 0.12) : .snappy(duration: 0.28, extraBounce: 0.06)
    }

    // MARK: - Per-state content

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .listening:
            LiveWaveform(level: controller.level, reduceMotion: reduceMotion)
            if controller.isHandsFree {
                caption("Hands-free")
            }

        case .starting:
            WorkingWaveform(reduceMotion: reduceMotion, quiet: true)

        case .transcribing:
            WorkingWaveform(reduceMotion: reduceMotion)
            caption("Transcribing")

        case .polishing:
            WorkingWaveform(reduceMotion: reduceMotion)
            HStack(spacing: 5) {
                Image(systemName: "sparkles")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(Theme.brandGradient)
                    .symbolEffect(.pulse, isActive: !reduceMotion)
                caption("Polishing")
            }

        case .finished(let text):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 14, weight: .semibold))
                .foregroundStyle(Theme.brandGradient)
                .contentTransition(.symbolEffect(.replace))
            Text(text)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 320, alignment: .leading)
                .transition(.opacity)

        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 13, weight: .semibold))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 12.5, weight: .medium))
                .foregroundStyle(.white.opacity(0.9))
                .lineLimit(2)
                .frame(maxWidth: 300, alignment: .leading)

        case .preparing(.loading(let fraction)):
            ProgressView(value: fraction)
                .progressViewStyle(.linear)
                .tint(Theme.violet)
                .frame(width: 90)
            caption("Downloading speech model · \(Int(fraction * 100))%")

        case .preparing(.warming):
            WorkingWaveform(reduceMotion: reduceMotion, quiet: true)
            caption("Getting ready")

        case .idle:
            EmptyView()
        }
    }

    private func caption(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 12.5, weight: .semibold, design: .rounded))
            .foregroundStyle(.white.opacity(0.78))
            .fixedSize()
            .transition(.opacity)
    }
}

// MARK: - Waveforms

private enum Bars {
    static let count = 13
    static let width: CGFloat = 3
    static let spacing: CGFloat = 2.5
    static let maxHeight: CGFloat = 20
    static let minHeight: CGFloat = 3

    /// Taller in the middle, like the icon, so even silence has a shape.
    static func envelope(_ index: Int) -> CGFloat {
        let center = CGFloat(count - 1) / 2
        let distance = abs(CGFloat(index) - center) / center
        return 1 - distance * 0.55
    }
}

/// Bars that follow your voice.
///
/// Growing out from the centre line, and shaped by a fixed envelope, is what
/// makes it read as a voice instead of a bar chart. Each bar gets a slightly
/// different share of the level so it looks alive rather than like one bar
/// copied thirteen times.
struct LiveWaveform: View {
    let level: Float
    var reduceMotion: Bool = false

    @State private var smoothed: [CGFloat] = Array(repeating: 0, count: Bars.count)

    var body: some View {
        HStack(alignment: .center, spacing: Bars.spacing) {
            ForEach(0..<Bars.count, id: \.self) { index in
                Capsule(style: .continuous)
                    .fill(Theme.barGradient)
                    .frame(
                        width: Bars.width,
                        height: max(
                            Bars.minHeight,
                            smoothed[index] * Bars.maxHeight * Bars.envelope(index)))
            }
        }
        .frame(height: Bars.maxHeight)
        .shadow(color: Theme.violet.opacity(0.8), radius: 5)
        .animation(reduceMotion ? nil : .spring(response: 0.16, dampingFraction: 0.72), value: smoothed)
        .onChange(of: level) { _, newValue in
            // Square root so quiet speech still visibly moves the bars.
            let target = CGFloat(sqrt(max(0, min(1, newValue))))
            smoothed = smoothed.indices.map { index in
                let jitter = 0.7 + 0.3 * CGFloat((index * 7 + Int(target * 40)) % 5) / 4
                return max(0.12, target * jitter)
            }
        }
        .accessibilityHidden(true)
    }
}

/// Bars that ripple on their own while Flow is working.
struct WorkingWaveform: View {
    var reduceMotion: Bool = false
    /// Smaller amplitude, for "starting" and "getting ready".
    var quiet: Bool = false

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 30, paused: reduceMotion)) { timeline in
            let t = timeline.date.timeIntervalSinceReferenceDate
            HStack(alignment: .center, spacing: Bars.spacing) {
                ForEach(0..<Bars.count, id: \.self) { index in
                    let phase = t * 5.5 - Double(index) * 0.45
                    let wave = (sin(phase) + 1) / 2
                    let amplitude: CGFloat = quiet ? 0.35 : 0.65
                    let height = reduceMotion
                        ? 0.3 : 0.15 + CGFloat(wave) * amplitude
                    Capsule(style: .continuous)
                        .fill(Theme.barGradient)
                        .opacity(0.55 + 0.45 * wave)
                        .frame(
                            width: Bars.width,
                            height: max(Bars.minHeight, height * Bars.maxHeight * Bars.envelope(index)))
                }
            }
            .frame(height: Bars.maxHeight)
        }
        .shadow(color: Theme.violet.opacity(0.6), radius: 4)
        .accessibilityHidden(true)
    }
}
