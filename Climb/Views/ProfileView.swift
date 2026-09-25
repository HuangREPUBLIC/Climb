import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var accounts: [LinkedAccount]
    @Query(sort: \Match.timestamp, order: .reverse) private var allMatches: [Match]
    @State private var showingLinkAccount = false
    @AppStorage("selectedGameFilter") private var selectedGameRaw = GameFilter.league.rawValue

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.modelContext) private var modelContext


    /// An iPad has room for more than the phone's five rows — filling that
    /// space is the point of the extra width, not stretching five rows across
    /// it and leaving the bottom half of the screen empty.
    private var previewCount: Int { horizontalSizeClass == .regular ? 10 : 5 }

    private var selectedGame: GameFilter {
        get { GameFilter(rawValue: selectedGameRaw) ?? .league }
        nonmutating set { selectedGameRaw = newValue.rawValue }
    }

    private var account: LinkedAccount? { accounts.first }
    /// Everything on this screen follows the game switcher.
    private var matches: [Match] { allMatches.filter { $0.game == selectedGame.game && $0.isOwnHistory } }
    private var leagueMatches: [Match] { matches.filter { $0.leagueStats != nil } }
    private var gamesWithMatches: Set<Game> { Set(allMatches.map(\.game)) }

    /// Current solo-queue rank, used as the context label on match rows.
    private var currentRankLabel: String {
        guard let account, let tier = account.rankTier, let division = account.rankDivision else {
            return "Unranked"
        }
        return RankEmblemService.displayName(tier: tier, division: division)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                VStack(spacing: 20) {
                    unpublishedMatchNotice
                    if !matches.isEmpty {
                        summaryCard
                        recentMatchesPreview
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            .readableContentWidth()
        }
        .background(Color(.systemGroupedBackground))
        // The standard system gesture for "get the latest data," so refreshing
        // no longer requires opening the sync sheet — a swipe down is a pattern
        // every iOS user already knows from Mail, News and the App Store.
        .refreshable { try? await MatchImportService.syncLinkedAccount(context: modelContext) }
        .navigationTitle("Profile")
        // Inline centres the title and removes the large-title block that sat
        // above the banner — that gap was what made the square top edge read
        // as disconnected from the rounded bottom.
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Match.self) { match in
            MatchDetailView(match: match)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GameFilterPicker(
                    selection: Binding(
                        get: { selectedGame },
                        set: { selectedGame = $0 }
                    ),
                    availableGames: gamesWithMatches
                )
            }
            ToolbarItem(placement: .primaryAction) {
                NavigationLink {
                    FriendComparisonView()
                } label: {
                    Image(systemName: "person.2")
                }
                // An icon-only control has no visible text for VoiceOver to
                // read, so without this it announces the SF Symbol's raw name
                // ("person dot 2") rather than what the button does.
                .accessibilityLabel("Compare with a friend")
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLinkAccount = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
                .accessibilityLabel(account == nil ? "Link Riot account" : "Sync Riot account")
            }
        }
        .sheet(isPresented: $showingLinkAccount) {
            LinkAccountView()
        }
    }

    // MARK: - Header

    /// The player's most-played champion, used as the banner's backdrop.
    private var bannerChampion: String? {
        Dictionary(grouping: leagueMatches) { $0.leagueStats?.champion ?? "" }
            .filter { !$0.key.isEmpty }
            .max { $0.value.count < $1.value.count }?
            .key
    }

    private var header: some View {
        ProfileBanner(
            profileIconID: account?.profileIconID,
            level: account?.summonerLevel,
            bannerChampion: bannerChampion
        ) {
            if let account {
                VStack(spacing: 12) {
                    BannerTitle(text: account.riotID)
                    RankChip(tier: account.rankTier, division: account.rankDivision, leaguePoints: account.leaguePoints)
                }
            } else {
                VStack(spacing: 10) {
                    Text("No Riot account linked")
                        .font(.title3.bold())
                        .foregroundStyle(.white)
                    Button("Link Riot Account") {
                        showingLinkAccount = true
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.white.opacity(0.9))
                    .foregroundStyle(Color.accentColor)
                }
            }
        }
    }

    /// Riot's match API can run behind the account itself — event queues in
    /// particular have gone unpublished for hours at a time. Without saying so,
    /// the app just shows a stale newest-match and reads as broken, which is
    /// exactly the wrong conclusion: nothing here can fix it, and re-syncing
    /// again will not help until Riot publishes the games.
    ///
    /// `lastRiotActivityDate` comes from Summoner-V4's `revisionDate`, which is
    /// already fetched on every sync, so this costs no extra request.
    @ViewBuilder
    private var unpublishedMatchNotice: some View {
        // Three hours of slack: a long game plus the gap between its start
        // timestamp and the account's revision is legitimately a couple of
        // hours, and a hint that cries wolf is worse than no hint.
        if let activity = account?.lastRiotActivityDate,
           let newest = matches.first?.timestamp,
           activity.timeIntervalSince(newest) > 3 * 60 * 60 {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "clock.badge.exclamationmark")
                    .foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Riot hasn't published your latest games")
                        .font(.subheadline.weight(.semibold))
                    Text("Your account was active \(activity.formatted(.relative(presentation: .named))), but the newest match Riot's API returns is from \(newest.formatted(.relative(presentation: .named))). Some game modes take a while to show up there.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(Theme.cardPadding)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.orange.opacity(0.12))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let wins = leagueMatches.filter(\.win).count
        let winRate = leagueMatches.isEmpty ? 0 : Double(wins) / Double(leagueMatches.count) * 100
        return StatSummaryCard(stats: [
            .init(icon: "gamecontroller.fill", label: "Matches", value: "\(matches.count)"),
            .init(icon: "percent", tint: winRate >= 50 ? Theme.win : Theme.loss, label: "Win rate", value: "\(Int(winRate.rounded()))%"),
            .init(icon: "trophy.fill", tint: .yellow, label: "Record", value: "\(wins)-\(leagueMatches.count - wins)")
        ])
    }

    // MARK: - Recent matches

    private var recentMatchesPreview: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Recent Matches").font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(matches.prefix(previewCount).enumerated()), id: \.element.id) { index, match in
                    NavigationLink(value: match) {
                        MatchRowView(match: match, rankLabel: currentRankLabel, showsChevron: true)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .denseRowScaling()
                    if index < min(matches.count, previewCount) - 1 {
                        Divider()
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .cardShadow()
        }
    }
}
