import SwiftUI

/// A queue or reflection tag, drawn the same way everywhere it appears — in
/// the editor, the filter bars, and the stats breakdown. Tinted when idle,
/// solid when selected.
struct TagChip: View {
    let text: String
    var isSelected: Bool = false

    var body: some View {
        let style = ChipStyle.of(text)
        // Idle chips keep dark text and carry the colour in the icon, fill
        // and border — several of these tints are too light to be text on white.
        HStack(spacing: 4) {
            Image(systemName: style.icon)
                .imageScale(.small)
                .foregroundStyle(isSelected ? Color.black : style.tint)
            Text(text)
                .foregroundStyle(isSelected ? Color.black : .primary)
        }
        .font(.caption.weight(.semibold))
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .background(isSelected ? style.tint : style.tint.opacity(0.12), in: Capsule())
        .overlay(Capsule().strokeBorder(style.tint.opacity(isSelected ? 0 : 0.35), lineWidth: 1))
        .lineLimit(1)
    }
}

/// Colour and icon by what a chip means: each queue its own colour, green
/// for a tag about something that went well, red for one that didn't, orange
/// for things outside the player's hands, blue for anything custom.
enum ChipStyle {
    static func of(_ text: String) -> (tint: Color, icon: String) {
        switch text {
        case "Ranked Solo/Duo", "Ranked TFT": return (Theme.fair, "trophy.fill")
        case "Ranked Flex": return (.orange, "person.3.fill")
        case "Normal (Draft)", "Normal (Blind)", "Normal TFT", "Quickplay": return (.blue, "gamecontroller.fill")
        case "Swiftplay", "Hyper Roll": return (.purple, "bolt.fill")
        case "ARAM", "ARAM Clash", "ARAM: Mayhem": return (.cyan, "snowflake")
        case "Clash": return (.pink, "flag.2.crossed.fill")
        case "Co-op vs. AI", "Tutorial": return (.mint, "cpu")
        case "URF", "One for All", "Ultimate Spellbook", "Nexus Blitz", "Arena", "Swarm", "Brawl", "Double Up":
            return (.indigo, "sparkles")

        case "Won lane": return (Theme.good, "arrow.up.right")
        case "Good vision": return (Theme.good, "eye.fill")
        case "Good macro": return (Theme.good, "map.fill")
        case "Good positioning": return (Theme.good, "scope")
        case "Highroll": return (Theme.good, "dice.fill")

        case "Lost lane": return (Theme.poor, "arrow.down.right")
        case "Died overextending": return (Theme.poor, "figure.fall")
        case "Poor vision": return (Theme.poor, "eye.slash.fill")
        case "Bad macro": return (Theme.poor, "map")
        case "Wrong build", "Bad items": return (Theme.poor, "hammer.fill")
        case "Threw a lead": return (Theme.poor, "chart.line.downtrend.xyaxis")
        case "Tilted": return (Theme.poor, "flame.fill")
        case "Bad positioning": return (Theme.poor, "scope")
        case "Lowroll": return (Theme.poor, "dice")
        case "Greedy econ": return (Theme.poor, "dollarsign.circle")
        case "Forced a comp": return (Theme.poor, "arrow.triangle.merge")

        case "Bad matchup": return (.orange, "person.2.fill")
        case "Team diff": return (.orange, "person.3.sequence.fill")
        case "Contested": return (.orange, "person.2.wave.2.fill")
        default: return (.blue, "tag.fill")
        }
    }
}

/// Picks a match's tags from a vocabulary, with a custom entry for whatever the
/// vocabulary doesn't cover.
///
/// Chips rather than a text field: a tag typed freehand every time is a tag
/// that never matches the last one, and the whole point of tagging is that the
/// stats screen can group by it afterwards.
struct TagEditor: View {
    @Binding var tags: [String]
    let vocabulary: [String]

    @State private var isAddingCustom = false
    @State private var customText = ""

    var body: some View {
        // Wraps, so the row can't run off the edge as the chips grow with the
        // user's text size.
        FlowLayout(spacing: 6) {
            ForEach(vocabulary, id: \.self) { tag in
                Button {
                    toggle(tag)
                } label: {
                    TagChip(text: tag, isSelected: tags.contains(tag))
                        // The capsule stays visually compact, but the button's
                        // own frame — what actually gets hit-tested — is held
                        // to Apple's 44pt minimum tap target. Below that, a
                        // caption-sized chip with 5pt vertical padding measures
                        // under 30pt tall, small enough to cause repeated
                        // mis-taps against its neighbours.
                        .frame(minHeight: 44)
                }
                .buttonStyle(PressableButtonStyle())
                .accessibilityAddTraits(tags.contains(tag) ? [.isSelected] : [])
            }

            Button {
                customText = ""
                isAddingCustom = true
            } label: {
                Label("Add", systemImage: "plus")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 5)
                    .background(Color.secondary.opacity(0.12))
                    .clipShape(Capsule())
                    .frame(minHeight: 44)
            }
            .buttonStyle(PressableButtonStyle())
        }
        // A quick tap-confirmation on every toggle — the chip's own colour
        // change already shows the new state, but a selection tick makes the
        // tap register instantly, before the eye catches up.
        .sensoryFeedback(.selection, trigger: tags)
        .alert("Add a tag", isPresented: $isAddingCustom) {
            TextField("e.g. Bad recall timing", text: $customText)
                .textInputAutocapitalization(.sentences)
            Button("Cancel", role: .cancel) { }
            Button("Add") { addCustom() }
        } message: {
            Text("Tags you add become suggestions on your other matches.")
        }
    }

    private func toggle(_ tag: String) {
        if let index = tags.firstIndex(of: tag) {
            tags.remove(at: index)
        } else {
            tags.append(tag)
        }
    }

    private func addCustom() {
        guard let tag = ReflectionTag.normalise(customText, against: vocabulary) else { return }
        if !tags.contains(tag) { tags.append(tag) }
    }
}

/// A horizontally scrolling filter row. Shown only where tags already exist —
/// an empty filter bar is a control that does nothing.
struct TagFilterBar: View {
    let tags: [String]
    @Binding var selection: String?

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(tags, id: \.self) { tag in
                    Button {
                        selection = selection == tag ? nil : tag
                    } label: {
                        TagChip(text: tag, isSelected: selection == tag)
                            .frame(minHeight: 44)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityAddTraits(selection == tag ? [.isSelected] : [])
                }
            }
            .padding(.horizontal)
        }
    }
}
