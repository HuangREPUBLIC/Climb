import SwiftUI
import SwiftData

struct MatchListView: View {
    @Query(sort: \Match.timestamp, order: .reverse) private var allMatches: [Match]
    @Query private var accounts: [LinkedAccount]
    @State private var showingLinkAccount = false
    @State private var tagFilter: String?
    @AppStorage("selectedGameFilter") private var selectedGameRaw = GameFilter.league.rawValue
    @Environment(\.modelContext) private var modelContext

    private var account: LinkedAccount? { accounts.first }

    @ScaledMetric(relativeTo: .subheadline) private var toolbarIconSize: CGFloat = 28

    /// Matches ProfileView — current solo rank as the row context label.
    private var currentRankLabel: String {
        guard let account, let tier = account.rankTier, let division = account.rankDivision else {
            return "Unranked"
        }
        return RankEmblemService.displayName(tier: tier, division: division)
    }
    /// Follows the game switcher in Profile — same @AppStorage key.
    private var matches: [Match] {
        allMatches.filter { $0.game == (GameFilter(rawValue: selectedGameRaw) ?? .league).game && $0.isOwnHistory }
    }

    /// Every tag the player has actually used on this game's matches. The
    /// filter bar is hidden when this is empty rather than shown as a control
    /// that does nothing.
    private var availableTags: [String] {
        var seen = Set<String>()
        return matches.flatMap(\.tags).filter { seen.insert($0).inserted }.sorted()
    }

    private var filteredMatches: [Match] {
        guard let tagFilter else { return matches }
        return matches.filter { $0.tags.contains(tagFilter) }
    }

    var body: some View {
        Group {
            if matches.isEmpty {
                ContentUnavailableView(
                    "No matches yet",
                    systemImage: "gamecontroller",
                    description: Text("Link a Riot account to import your match history.")
                )
            } else {
                VStack(spacing: 0) {
                    if !availableTags.isEmpty {
                        TagFilterBar(tags: availableTags, selection: $tagFilter)
                            .background(Color(.systemGroupedBackground))
                    }

                    if filteredMatches.isEmpty, let tagFilter {
                        ContentUnavailableView(
                            "No matches tagged \(tagFilter)",
                            systemImage: "tag",
                            description: Text("Tap the tag again to clear the filter.")
                        )
                    } else {
                        List(filteredMatches) { match in
                            NavigationLink(value: match) {
                                MatchRowView(match: match, rankLabel: currentRankLabel)
                            }
                            .denseRowScaling()
                        }
                        // Same standard pull-to-refresh gesture as Profile —
                        // one consistent way to get new matches everywhere the
                        // match list appears, rather than only from the sheet.
                        .refreshable { await refresh() }
                    }
                }
            }
        }
        .navigationTitle("Matches")
        .navigationDestination(for: Match.self) { match in
            MatchDetailView(match: match)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLinkAccount = true
                } label: {
                    accountLabel
                }
            }
        }
        .sheet(isPresented: $showingLinkAccount) {
            LinkAccountView()
        }
    }

    private func refresh() async {
        guard let account, let platform = RiotPlatform(rawValue: account.platform) else { return }
        try? await MatchImportService.linkAndSync(
            gameName: account.riotGameName,
            tagLine: account.riotTagline,
            platform: platform,
            gamesToSync: Set(account.syncedGames),
            context: modelContext
        )
    }

    @ViewBuilder
    private var accountLabel: some View {
        if let account {
            HStack(spacing: 6) {
                if let iconID = account.profileIconID {
                    ProfileIconView(profileIconID: iconID, size: toolbarIconSize)
                } else {
                    Image(systemName: "person.crop.circle.fill")
                }
                Text(account.riotGameName)
                    .font(.subheadline)
            }
        } else {
            Label("Link Account", systemImage: "person.crop.circle.badge.plus")
        }
    }
}
