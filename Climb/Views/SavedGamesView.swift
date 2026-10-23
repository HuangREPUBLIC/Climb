import SwiftUI
import SwiftData

/// Games bookmarked from a match screen or a card's long-press menu, your
/// own and other players', newest first. Only unsaving one removes it.
struct SavedGamesView: View {
    /// The Matches stack's path, so a saved game opens like any other match.
    @Binding var path: NavigationPath
    @Query(filter: #Predicate<Match> { $0.isSaved }, sort: \Match.timestamp, order: .reverse)
    private var saved: [Match]

    var body: some View {
        ScrollView {
            Group {
                if saved.isEmpty {
                    ContentUnavailableView(
                        "No saved games",
                        systemImage: "bookmark",
                        description: Text("Tap the bookmark on a match, or long-press its card, to keep it here.")
                    )
                    .padding(.top, 60)
                } else {
                    MatchCardList(matches: saved, open: { path.append($0) }, showsPlayer: true)
                }
            }
            .padding()
            .readableContentWidth()
        }
        .screen("Saved Games")
    }
}
