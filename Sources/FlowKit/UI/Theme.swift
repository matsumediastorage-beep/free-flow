import SwiftUI

/// Free Flow's visual language, in one place.
///
/// Taken from the app icon: a near-black glass tile with violet light coming
/// through it. Violet is the only accent, and it means one thing — "Flow is
/// listening or working". Everything else stays neutral and native so the
/// dashboard still feels like a Mac app rather than a web page in a window.
enum Theme {

    // MARK: Brand colors

    static let violet = Color(red: 0.55, green: 0.36, blue: 0.97)  // #8B5CF6
    static let indigo = Color(red: 0.39, green: 0.40, blue: 0.95)  // #6366F1
    static let orchid = Color(red: 0.75, green: 0.52, blue: 0.99)  // #C084FC
    static let glow = Color(red: 0.85, green: 0.72, blue: 1.00)  // bar highlights

    /// The overlay is always dark, like the icon, whatever the system theme —
    /// it floats over everything, and a dark pill reads on light and dark
    /// windows alike.
    static let pillBase = Color(red: 0.06, green: 0.05, blue: 0.09)

    static let brandGradient = LinearGradient(
        colors: [orchid, violet, indigo],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
    )

    static let barGradient = LinearGradient(
        colors: [glow, orchid, violet],
        startPoint: .top,
        endPoint: .bottom
    )

    // MARK: Type

    static func display(_ size: CGFloat, weight: Font.Weight = .bold) -> Font {
        .system(size: size, weight: weight, design: .rounded)
    }
}

/// A rounded, softly-bordered surface for grouping dashboard content.
struct Card<Content: View>: View {
    let padding: CGFloat
    let content: () -> Content

    @Environment(\.colorScheme) private var colorScheme

    init(padding: CGFloat = 18, @ViewBuilder content: @escaping () -> Content) {
        self.padding = padding
        self.content = content
    }

    var body: some View {
        content()
            .padding(padding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(nsColor: .controlBackgroundColor))
                    .opacity(colorScheme == .dark ? 0.55 : 0.9)
            }
            .overlay {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(Color.primary.opacity(colorScheme == .dark ? 0.08 : 0.06), lineWidth: 1)
            }
    }
}

/// Small uppercase label above a card's content.
struct SectionLabel: View {
    let text: String
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundStyle(.secondary)
    }
}

/// The brand mark: a miniature of the icon's glowing bars.
struct BrandMark: View {
    var size: CGFloat = 28
    private static let heights: [CGFloat] = [0.3, 0.55, 0.85, 0.55, 0.3]

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .fill(Theme.pillBase)
            RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                .strokeBorder(Theme.brandGradient, lineWidth: max(1, size * 0.05))
            HStack(spacing: size * 0.06) {
                ForEach(Array(Self.heights.enumerated()), id: \.offset) { _, h in
                    Capsule()
                        .fill(Theme.barGradient)
                        .frame(width: size * 0.08, height: size * 0.6 * h)
                }
            }
        }
        .frame(width: size, height: size)
        .shadow(color: Theme.violet.opacity(0.45), radius: size * 0.18)
        .accessibilityHidden(true)
    }
}
