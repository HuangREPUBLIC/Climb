import SwiftUI

/// A Riot ID and the server it lives on — everywhere the app asks for a player.
///
/// The name and tag are one control split by a "#", because that is how a
/// Riot ID is written everywhere else; two separate rows made the player
/// take their own ID apart to enter it.
struct RiotIDInput: View {
    enum Field { case name, tag }

    @Binding var gameName: String
    @Binding var tagLine: String
    @Binding var platform: RiotPlatform
    /// Owned by the screen so its primary button can dismiss the keyboard.
    var focus: FocusState<Field?>.Binding
    var submitLabel: SubmitLabel = .done
    /// Return on the tag field. Dismisses the keyboard when not set.
    var onSubmit: (() -> Void)?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .caption) private var dividerHeight: CGFloat = 20

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            field

            HStack {
                Label("Server", systemImage: "globe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                serverMenu
            }
        }
    }

    @ViewBuilder
    private var field: some View {
        let name = TextField("Game name", text: $gameName)
            .focused(focus, equals: .name)
            .submitLabel(.next)
            .onSubmit { focus.wrappedValue = .tag }

        let tag = HStack(spacing: 2) {
            Text("#").foregroundStyle(.tertiary)
            TextField("TAG", text: $tagLine)
                .focused(focus, equals: .tag)
                .submitLabel(submitLabel)
                .onSubmit {
                    if let onSubmit { onSubmit() } else { focus.wrappedValue = nil }
                }
        }

        Group {
            // Side by side reads as one identity; at accessibility sizes the
            // tag would be squeezed to a couple of characters, so it stacks.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    name
                    Divider()
                    tag
                }
            } else {
                HStack(spacing: 6) {
                    name
                    Divider().frame(height: dividerHeight)
                    tag.frame(maxWidth: 110, alignment: .leading)
                }
            }
        }
        .font(.body)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    /// A menu rather than a `Picker` row, matching the game switcher in the
    /// navigation bar — the app already has one capsule-shaped chooser.
    private var serverMenu: some View {
        Menu {
            Picker("Server", selection: $platform) {
                ForEach(RiotPlatform.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(platform.displayName)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .scaledFont(9, weight: .semibold)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.accent.opacity(0.12))
            .clipShape(Capsule())
        }
    }
}
