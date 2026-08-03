import SwiftUI

/// Contents of the floating pill. Mirrors `DictationState`.
struct OverlayView: View {
    @Bindable var controller: DictationController

    var body: some View {
        HStack(spacing: 12) {
            content
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 12)
        .frame(minWidth: 200)
        .background {
            Capsule(style: .continuous)
                .fill(.ultraThinMaterial)
                .overlay {
                    Capsule(style: .continuous)
                        .strokeBorder(.white.opacity(0.12), lineWidth: 1)
                }
                .shadow(color: .black.opacity(0.28), radius: 16, y: 6)
        }
        .animation(.easeOut(duration: 0.18), value: controller.state)
    }

    @ViewBuilder
    private var content: some View {
        switch controller.state {
        case .listening:
            WaveformView(level: controller.level)
            Text(controller.isHandsFree ? "Hands-free" : "Listening")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

        case .transcribing:
            ProgressView()
                .controlSize(.small)
                .scaleEffect(0.8)
            Text("Transcribing…")
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

        case .finished(let text):
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.green)
            Text(text)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: 280, alignment: .leading)

        case .failed(let message):
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 15))
                .foregroundStyle(.orange)
            Text(message)
                .font(.system(size: 13, weight: .medium, design: .rounded))
                .lineLimit(2)
                .frame(maxWidth: 280, alignment: .leading)

        case .preparing(let fraction):
            ProgressView(value: fraction)
                .controlSize(.small)
                .frame(width: 90)
            Text("Loading speech model… \(Int(fraction * 100))%")
                .font(.system(size: 12, weight: .medium, design: .rounded))
                .foregroundStyle(.secondary)

        case .idle:
            EmptyView()
        }
    }
}

/// Live input-level bars. A short history of recent levels scrolls leftward, so
/// it reads as a waveform rather than a single jumping meter.
struct WaveformView: View {
    let level: Float

    private static let barCount = 14
    @State private var history: [Float] = Array(repeating: 0.04, count: barCount)

    var body: some View {
        HStack(alignment: .center, spacing: 2.5) {
            ForEach(Array(history.enumerated()), id: \.offset) { _, value in
                Capsule()
                    .fill(.tint)
                    .frame(width: 3, height: max(3, CGFloat(value) * 26))
            }
        }
        .frame(height: 26)
        .animation(.easeOut(duration: 0.09), value: history)
        .onChange(of: level) { _, newValue in
            history.removeFirst()
            // Square-root curve: quiet speech still shows visible movement.
            history.append(max(0.04, sqrt(newValue)))
        }
    }
}
