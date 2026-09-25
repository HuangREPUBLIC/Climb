import SwiftUI
import SwiftData

/// The Matches tab (战绩): who you are, how you've been playing, and every
/// synced game on one scroll, the way 掌盟 lays it out — rather than a profile
/// previewing five games and a second tab listing the same ones again.
struct ProfileView: View {
    @Query private var accounts: [LinkedAccount]
    @Query(sort: \Match.timestamp, order: .reverse) private var allMatches: [Match]
    @AppStorage("selectedGame") private var selectedGame: Game = .league
    @State private var showingLinkAccount = false
    @State private var queueFilter: String?
    @State private var tagFilter: String?
    @State private var isLoadingOlder = false
    @State private var reachedEnd = false
    @State private var olderLoadFailed = false

    @Environment(\.modelContext) private var modelContext

    private var account: LinkedAccount? { accounts.first }
    /// Everything on this screen follows the game switcher.
    private var matches: [Match] { allMatches.filter { $0.game == selectedGame && $0.isOwnHistory } }
    private var filteredMatches: [Match] {
        matches.filter { match in
            (queueFilter.map { match.queueType == $0 } ?? true)
                && (tagFilter.map { match.tags.contains($0) } ?? true)
        }
    }
    /// Modes the player actually has games in, most played first.
    private var queues: [String] {
        Dictionary(grouping: matches, by: \.queueType)
            .sorted { $0.value.count > $1.value.count }
            .map(\.key)
    }
    private var tags: [String] {
        var seen = Set<String>()
        return matches.flatMap(\.tags).filter { seen.insert($0).inserted }.sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                header

                VStack(spacing: 16) {
                    unpublishedMatchNotice
                    if !matches.isEmpty { summaryCard }
                }
                .padding(.horizontal)

                if queues.count > 1 {
                    TagFilterBar(tags: queues, selection: $queueFilter)
                        .padding(.vertical, -8)
                }
                if !tags.isEmpty {
                    TagFilterBar(tags: tags, selection: $tagFilter)
                        .padding(.vertical, -8)
                }

                Group {
                    if matches.isEmpty {
                        ContentUnavailableView(
                            "No matches yet",
                            systemImage: "gamecontroller",
                            description: Text("Link a Riot account to import your match history.")
                        )
                    } else if filteredMatches.isEmpty {
                        ContentUnavailableView(
                            "No matches for this filter",
                            systemImage: "line.3.horizontal.decrease",
                            description: Text("Tap the selected filter again to clear it.")
                        )
                    } else {
                        matchList
                    }
                    if selectedGame == .league, account != nil, !matches.isEmpty {
                        loadOlderButton
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            .readableContentWidth()
        }
        .background(Color(.systemGroupedBackground))
        // The standard system gesture for "get the latest data".
        .refreshable { try? await MatchImportService.syncLinkedAccount(context: modelContext) }
        .navigationTitle("Matches")
        // Inline keeps the banner flush under the bar instead of a large-title
        // block floating above it.
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: Match.self) { match in
            MatchDetailView(match: match)
        }
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GameFilterPicker(selection: $selectedGame, availableGames: Set(allMatches.map(\.game)))
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
        .onChange(of: selectedGame) {
            queueFilter = nil
            tagFilter = nil
        }
    }

    // MARK: - Header

    /// The player's most-played champion, used as the banner's backdrop.
    private var bannerChampion: String? {
        Dictionary(grouping: matches.compactMap(\.leagueStats?.champion)) { $0 }
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
    /// particular go unpublished for hours. Without saying so the app shows a
    /// stale newest match and reads as broken, when nothing here can fix it.
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

    /// Follows the filters, so picking "Ranked Solo/Duo" answers "how am I
    /// doing in ranked" without a separate screen.
    private var summaryCard: some View {
        let games = filteredMatches
        let wins = games.filter { $0.tftStats.map { $0.placement <= 4 } ?? $0.win }.count
        let winRate = games.isEmpty ? 0 : Double(wins) / Double(games.count) * 100
        let lines = games.compactMap(\.leagueStats)
        // Totals over totals, as op.gg does, so one 10/0/10 game can't pass
        // for an average.
        let kda = Double(lines.map { $0.kills + $0.assists }.reduce(0, +))
            / Double(max(lines.map(\.deaths).reduce(0, +), 1))

        return StatSummaryCard(stats: [
            .init(icon: "percent", tint: winRate >= 50 ? Theme.win : Theme.loss, label: "Win rate", value: "\(Int(winRate.rounded()))%"),
            lines.isEmpty
                ? .init(icon: "gamecontroller.fill", label: "Games", value: "\(games.count)")
                : .init(icon: "bolt.fill", label: "KDA", value: String(format: "%.2f", kda)),
            .init(icon: "trophy.fill", tint: .yellow, label: "Record", value: "\(wins)W \(games.count - wins)L")
        ])
    }

    // MARK: - Matches

    private var matchList: some View {
        LazyVStack(spacing: 0) {
            ForEach(Array(filteredMatches.enumerated()), id: \.element.id) { index, match in
                if index > 0 { Divider() }
                NavigationLink(value: match) {
                    MatchRowView(match: match)
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .cardSurface()
    }

    /// A button, not infinite scroll: each page costs ~40 requests against a
    /// personal key's 100 per two minutes, so loading more is a deliberate act.
    private var loadOlderButton: some View {
        Button {
            isLoadingOlder = true
            Task {
                do {
                    let added = try await MatchImportService.loadOlderMatches(context: modelContext)
                    reachedEnd = added == 0
                    olderLoadFailed = false
                } catch {
                    // A rate limit isn't the end of history — offer a retry.
                    olderLoadFailed = true
                }
                isLoadingOlder = false
            }
        } label: {
            HStack(spacing: 8) {
                if isLoadingOlder { ProgressView().controlSize(.small) }
                Text(isLoadingOlder ? "Loading…"
                     : olderLoadFailed ? "Couldn't load — tap to retry"
                     : reachedEnd ? "No older matches found"
                     : "Load older matches")
                    .font(.subheadline.weight(.semibold))
            }
            .foregroundStyle(Theme.accent)
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(isLoadingOlder)
    }
}
