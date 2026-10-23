import SwiftUI

/// Compact LoL / TFT switcher for the navigation bar's leading edge. Only games Riot's public API serves are
/// offered: Wild Rift has no public match API, and VALORANT's needs a production key.
struct GameFilterPicker: ToolbarContent {
    @Binding var selection: Game
    /// Games that actually have synced matches; the rest are labelled as empty.
    var availableGames: Set<Game>

    var body: some ToolbarContent {
        // Hidden when the only other game is empty, unless an empty game is selected, so there's a way back.
        if availableGames.count > 1 || !availableGames.contains(selection) {
            ToolbarItem(placement: .topBarLeading) {
                Menu {
                    ForEach(Game.allCases) { game in
                        Button(game.rawValue + (availableGames.contains(game) ? "" : " (no matches)"), systemImage: game.systemImageName) {
                            selection = game
                        }
                    }
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: selection.systemImageName)
                            .font(.caption)
                        Text(selection.shortName)
                            .font(.subheadline.weight(.semibold))
                        Image(systemName: "chevron.up.chevron.down")
                            .scaledFont(9, weight: .semibold)
                    }
                    // No capsule of its own: the toolbar item's glass is the background.
                    .foregroundStyle(.primary)
                    .padding(.horizontal, 4)
                }
            }
        }
    }
}
