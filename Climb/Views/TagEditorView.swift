import SwiftUI

/// One reflection tag, drawn the same way everywhere it appears — in the
/// editor, on a match row filter, and in the stats breakdown.
struct TagChip: View {
    let text: String
    var isSelected: Bool = true
    var tint: Color = Theme.accent

    var body: some View {
        Text(text)
            .font(.caption.weight(.medium))
            .foregroundStyle(isSelected ? tint : .secondary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            // A translucent fill rather than a system grey: the chip sits on a
            // white card in the editor and on the grouped background in the
            // filter bar, and a fixed grey disappears against one of them.
            .background(isSelected ? tint.opacity(0.14) : Color.secondary.opacity(0.12))
            .overlay(
                Capsule().strokeBorder(isSelected ? tint.opacity(0.35) : .clear, lineWidth: 1)
            )
            .clipShape(Capsule())
            .lineLimit(1)
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
            }
            .buttonStyle(PressableButtonStyle())
        }
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
                    }
                    .buttonStyle(PressableButtonStyle())
                    .accessibilityAddTraits(selection == tag ? [.isSelected] : [])
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
    }
}
