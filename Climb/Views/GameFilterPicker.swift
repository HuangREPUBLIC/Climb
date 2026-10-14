import SwiftUI

/// Compact LoL / TFT switcher for the navigation bar's leading edge.
///
/// Only games Riot's public API serves are offered. Wild Rift has no public
/// match API at all — the Chinese companion app can show it because it's a
/// first-party Tencent client — and VALORANT's needs a production key.
struct GameFilterPicker: View {
    @Binding var selection: Game
    /// Games that actually have synced matches; the rest are labelled so it's
    /// obvious they exist but have nothing in them yet.
    var availableGames: Set<Game> = Set(Game.allCases)

    /// A switcher whose only other choice is empty is noise. It still shows
    /// while an empty game is selected, so there is a way back.
    static func isNeeded(selection: Game, availableGames: Set<Game>) -> Bool {
        availableGames.count > 1 || !availableGames.contains(selection)
    }

    var body: some View {
        Menu {
            ForEach(Game.allCases) { game in
                Button {
                    selection = game
                } label: {
                    Label {
                        Text(game.rawValue + (availableGames.contains(game) ? "" : " (no matches)"))
                    } icon: {
                        Image(systemName: game.systemImageName)
                    }
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
            // No capsule of its own: the toolbar item's glass is the
            // background, and text follows the bar's colour scheme.
            .foregroundStyle(.primary)
            .padding(.horizontal, 4)
        }
    }
}
