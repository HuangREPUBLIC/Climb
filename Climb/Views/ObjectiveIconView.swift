import SwiftUI

/// Real in-game objective art — each elemental drake has its own icon, the
/// way the scoreboard in-game and in the reference app shows them.
struct ObjectiveIconView: View {
    let url: URL?
    var size: CGFloat = 22

    var body: some View {
        AsyncImage(url: url) { phase in
            if let image = phase.image {
                image.resizable().scaledToFit()
            } else {
                Circle().fill(.secondary.opacity(0.15))
            }
        }
        .frame(width: size, height: size)
    }
}

/// An objective count as icon + number, used for both per-player and
/// per-team objective rows.
struct ObjectiveCountChip: View {
    let url: URL?
    let label: String
    let count: Int
    var iconSize: CGFloat = 26
    var showsLabel: Bool = true

    var body: some View {
        VStack(spacing: 3) {
            ObjectiveIconView(url: url, size: iconSize)
            Text("\(count)")
                .font(.caption.weight(.bold).monospacedDigit())
            if showsLabel {
                Text(label)
                    .scaledFont(9)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity)
    }
}
