import SwiftUI

/// Names, clients and jargon the AI pass should always spell right.
///
/// This is the single most effective thing you can do for accuracy: the speech
/// model has never heard of "Matsu" or "Sheephorn", but once they're here the
/// AI pass maps anything that sounds like them onto the right spelling.
struct DictionaryView: View {
    @Bindable var settings: Settings
    @State private var newTerm = ""
    @FocusState private var fieldFocused: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Your dictionary")
                        .font(Theme.display(24))
                    Text(
                        "Add names, clients, products and jargon. When you say something that sounds like one of these, Free Flow spells it exactly this way."
                    )
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                }

                Card {
                    VStack(alignment: .leading, spacing: 14) {
                        HStack(spacing: 10) {
                            Image(systemName: "plus.circle.fill")
                                .font(.system(size: 18))
                                .foregroundStyle(Theme.brandGradient)
                            TextField("Add a word or name, e.g. Supabase", text: $newTerm)
                                .textFieldStyle(.plain)
                                .font(.system(size: 14))
                                .focused($fieldFocused)
                                .onSubmit(add)
                            Button("Add", action: add)
                                .buttonStyle(.borderedProminent)
                                .disabled(newTerm.trimmingCharacters(in: .whitespaces).isEmpty)
                        }
                        Text("Tip: paste a comma-separated list to add several at once.")
                            .font(.system(size: 11))
                            .foregroundStyle(.tertiary)
                    }
                }

                if settings.vocabulary.isEmpty {
                    Card {
                        HStack(spacing: 12) {
                            Image(systemName: "character.book.closed")
                                .font(.system(size: 20))
                                .foregroundStyle(Theme.brandGradient)
                            Text("Nothing here yet. Start with the names you say most: people, clients, your company, tools you use.")
                                .font(.system(size: 12.5))
                                .foregroundStyle(.secondary)
                        }
                    }
                } else {
                    VStack(alignment: .leading, spacing: 10) {
                        SectionLabel(text: "\(settings.vocabulary.count) words")
                        ChipFlowLayout(spacing: 8) {
                            ForEach(settings.vocabulary, id: \.self) { term in
                                TermChip(term: term) {
                                    settings.vocabulary.removeAll { $0 == term }
                                }
                            }
                        }
                    }
                }

                Card {
                    HStack(alignment: .top, spacing: 12) {
                        Image(systemName: "lightbulb")
                            .foregroundStyle(Theme.violet)
                        Text(
                            "The dictionary is used by AI cleanup (Claude or Apple on-device). With cleanup off, the raw speech model has no way to use it."
                        )
                        .font(.system(size: 12))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(24)
            .frame(maxWidth: 820, alignment: .leading)
            .frame(maxWidth: .infinity)
        }
    }

    private func add() {
        let terms = newTerm
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        for term in terms where !settings.vocabulary.contains(term) {
            settings.vocabulary.append(term)
        }
        newTerm = ""
        fieldFocused = true
    }
}

private struct TermChip: View {
    let term: String
    let onRemove: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 6) {
            Text(term)
                .font(.system(size: 12.5, weight: .medium))
            Button(action: onRemove) {
                Image(systemName: "xmark")
                    .font(.system(size: 8.5, weight: .bold))
            }
            .buttonStyle(.borderless)
            .foregroundStyle(hovering ? Theme.violet : Color.secondary)
            .help("Remove")
        }
        .padding(.leading, 12)
        .padding(.trailing, 9)
        .padding(.vertical, 6)
        .background(Capsule().fill(Theme.violet.opacity(hovering ? 0.18 : 0.10)))
        .overlay(Capsule().strokeBorder(Theme.violet.opacity(0.25), lineWidth: 1))
        .onHover { hovering = $0 }
    }
}

/// Wraps chips onto as many lines as they need.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var widest: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth, x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            x += size.width + spacing
            widest = max(widest, x - spacing)
            rowHeight = max(rowHeight, size.height)
        }
        let width = maxWidth.isFinite ? maxWidth : widest
        return CGSize(width: width, height: y + rowHeight)
    }

    func placeSubviews(
        in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()
    ) {
        var x = bounds.minX
        var y = bounds.minY
        var rowHeight: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > bounds.maxX, x > bounds.minX {
                x = bounds.minX
                y += rowHeight + spacing
                rowHeight = 0
            }
            subview.place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
            x += size.width + spacing
            rowHeight = max(rowHeight, size.height)
        }
    }
}
