import SwiftUI

/// Shared "which game am I looking at" selection, mirroring the game switcher
/// in the top-left of the reference app's profile.
///
/// Only games Riot's public API actually serves are offered. Wild Rift (LoL
/// Mobile) has no public match or account API at all — the Chinese companion
/// app can show it because it's a first-party Tencent client wired into the
/// CN backend, which third-party keys cannot reach. VALORANT is likewise out
/// of reach on a personal development key.
enum GameFilter: String, CaseIterable, Identifiable {
    case league
    case tft

    var id: String { rawValue }

    var game: Game {
        switch self {
        case .league: return .league
        case .tft: return .tft
        }
    }

    var title: String { game.rawValue }
    var shortTitle: String { game.shortName }
    var systemImage: String { game.systemImageName }
}

/// Compact switcher for the navigation bar's leading edge.
struct GameFilterPicker: View {
    @Binding var selection: GameFilter
    /// Games that actually have synced matches; the rest are labelled so it's
    /// obvious they exist but have nothing in them yet.
    var availableGames: Set<Game> = [.league, .tft]

    var body: some View {
        Menu {
            ForEach(GameFilter.allCases) { filter in
                Button {
                    selection = filter
                } label: {
                    Label {
                        Text(filter.title + (availableGames.contains(filter.game) ? "" : " (no matches)"))
                    } icon: {
                        Image(systemName: filter.systemImage)
                    }
                }
            }
        } label: {
            HStack(spacing: 5) {
                Image(systemName: selection.systemImage)
                    .font(.caption)
                Text(selection.shortTitle)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .scaledFont(9, weight: .semibold)
            }
            .foregroundStyle(.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(Capsule())
        }
    }
}
