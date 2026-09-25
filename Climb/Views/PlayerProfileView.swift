import SwiftUI
import SwiftData

/// Another player's page, opening on their profile — same banner, stat cards
/// and match rows as your own Profile tab — with paging through their full
/// match history rather than a fixed handful.
struct PlayerProfileView: View {
    let puuid: String
    let riotIdGameName: String
    let riotIdTagline: String
    let region: RiotRegion
    var platform: RiotPlatform?

    @State private var profile: OtherPlayerProfile?
    @State private var matches: [OtherPlayerMatchSummary] = []
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var reachedEnd = false
    @State private var errorMessage: String?
    /// The other player's match, fetched and cached on demand when a row is
    /// tapped. Drilling in from here reaches the same detail screen as your own
    /// matches, whose scoreboard links to every participant's profile — so the
    /// two screens form a loop you can keep following outward.
    @State private var browsedMatch: Match?
    @State private var loadingMatchID: String?

    @Environment(\.modelContext) private var modelContext

    private let pageSize = 15

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .subheadline) private var rawPortraitSize: CGFloat = 44
    private var portraitSize: CGFloat { rawPortraitSize.capped(at: 72) }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header

                VStack(spacing: 20) {
                    if !matches.isEmpty {
                        summaryCard
                        matchesCard
                    } else if isLoading {
                        ProgressView().padding(.top, 40)
                    } else if let errorMessage {
                        ContentUnavailableView(
                            "Couldn't load matches",
                            systemImage: "exclamationmark.triangle",
                            description: Text(errorMessage)
                        )
                    } else {
                        ContentUnavailableView("No recent matches", systemImage: "gamecontroller")
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            .readableContentWidth()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("\(riotIdGameName)#\(riotIdTagline)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $browsedMatch) { match in
            MatchDetailView(match: match)
        }
        .task {
            if let platform, profile == nil {
                profile = await PlayerProfileService.profile(puuid: puuid, platform: platform)
            }
            await loadPage(reset: true)
        }
    }

    // MARK: - Header

    /// The champion this player shows up on most, used as their banner.
    /// Same treatment as your own profile — see ProfileView.
    private var bannerChampion: String? {
        Dictionary(grouping: matches, by: \.champion)
            .max { $0.value.count < $1.value.count }?
            .key
    }

    private var header: some View {
        ProfileBanner(
            profileIconID: profile?.profileIconID,
            level: profile?.summonerLevel,
            bannerChampion: bannerChampion
        ) {
            VStack(spacing: 12) {
                BannerTitle(text: "\(riotIdGameName)#\(riotIdTagline)")
                if let profile {
                    RankChip(tier: profile.rankTier, division: profile.rankDivision, leaguePoints: profile.leaguePoints)
                }
            }
        }
    }

    // MARK: - Summary

    private var summaryCard: some View {
        let wins = matches.filter(\.win).count
        let winRate = matches.isEmpty ? 0 : Double(wins) / Double(matches.count) * 100
        let avgKDA = matches.isEmpty ? 0 : matches.map(kdaValue).reduce(0, +) / Double(matches.count)
        return StatSummaryCard(stats: [
            .init(icon: "gamecontroller.fill", label: "Loaded", value: "\(matches.count)"),
            .init(icon: "percent", tint: winRate >= 50 ? Theme.win : Theme.loss, label: "Win rate", value: "\(Int(winRate.rounded()))%"),
            .init(icon: "bolt.fill", label: "Avg KDA", value: String(format: "%.2f", avgKDA))
        ])
    }

    private func kdaValue(_ match: OtherPlayerMatchSummary) -> Double {
        match.deaths == 0
            ? Double(match.kills + match.assists)
            : Double(match.kills + match.assists) / Double(match.deaths)
    }

    // MARK: - Matches

    private var matchesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Match history").font(.headline)

            VStack(spacing: 0) {
                ForEach(Array(matches.enumerated()), id: \.element.id) { index, match in
                    Button {
                        open(match)
                    } label: {
                        HStack(spacing: 8) {
                            matchRow(match)
                            if loadingMatchID == match.id {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "chevron.right")
                                    .font(.caption2.weight(.semibold))
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(loadingMatchID != nil)
                    .denseRowScaling()
                    if index < matches.count - 1 { Divider() }
                }

                if !reachedEnd {
                    Divider()
                    Button {
                        Task { await loadPage(reset: false) }
                    } label: {
                        HStack(spacing: 6) {
                            if isLoadingMore {
                                ProgressView().controlSize(.small)
                            } else {
                                Image(systemName: "arrow.down.circle")
                            }
                            Text(isLoadingMore ? "Loading…" : "Load more")
                        }
                        .font(.subheadline.weight(.medium))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(PressableButtonStyle())
                    .disabled(isLoadingMore)
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .cardShadow()
        }
    }

    /// Same two-row shape as MatchRowView so all three match lists in the app
    /// (Profile, Matches, another player's profile) read identically.
    private func matchRow(_ match: OtherPlayerMatchSummary) -> some View {
        let outcome = Text(match.win ? "Victory" : "Defeat")
            .font(.subheadline.weight(.bold))
            .foregroundStyle(match.win ? Theme.win : Theme.loss)

        // Concatenated at accessibility sizes — see MatchRowView: five
        // separate views each shrink independently and the kills truncate
        // first. The normal path keeps the original spaced row.
        let kda = (Text("\(match.kills)")
            + Text("/").foregroundStyle(.tertiary)
            + Text("\(match.deaths)").foregroundStyle(.red)
            + Text("/").foregroundStyle(.tertiary)
            + Text("\(match.assists)"))
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
            .accessibilityLabel("\(match.kills) kills, \(match.deaths) deaths, \(match.assists) assists")

        return HStack(alignment: .center, spacing: 12) {
            ChampionIconView(championName: match.champion, size: portraitSize)

            VStack(alignment: .leading, spacing: 4) {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 4) { outcome; kda }
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        outcome
                        Spacer(minLength: 4)
                        kda
                    }
                }

                // See MatchRowView: one line normally, stacked only at
                // accessibility sizes.
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(subtitle(for: match))
                            Text(match.timestamp, format: Self.timestampFormat)
                        }
                    } else {
                        HStack(spacing: 5) {
                            Text(subtitle(for: match))
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 6)
                            Text(match.timestamp, format: Self.timestampFormat)
                                .fixedSize()
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 5)
    }

    private static let timestampFormat = Date.FormatStyle()
        .month(.abbreviated)
        .day()
        .hour(.defaultDigits(amPM: .abbreviated))
        .minute()

    /// Mode | rank, matching MatchRowView. The rank is this player's current
    /// tier (Riot exposes no per-match tier).
    private func subtitle(for match: OtherPlayerMatchSummary) -> String {
        var parts = [match.queueType]
        if let tier = profile?.rankTier, let division = profile?.rankDivision {
            parts.append(RankEmblemService.displayName(tier: tier, division: division))
        } else if profile != nil {
            parts.append("Unranked")
        }
        return parts.joined(separator: " | ")
    }

    // MARK: - Loading

    /// Riot's match detail is fetched on demand rather than kept from the list
    /// load: `recentMatches` already downloads the full detail for every row
    /// and discards all but one participant, but holding fifteen full matches
    /// in memory to serve a tap that may never come is the wrong trade. The
    /// second visit to a match is free — `browsedMatch` returns the cached row.
    private func open(_ summary: OtherPlayerMatchSummary) {
        guard loadingMatchID == nil else { return }
        loadingMatchID = summary.id
        Task {
            defer { loadingMatchID = nil }
            guard let detail = try? await RiotAPIClient.shared.fetchMatch(
                matchID: summary.id,
                region: region
            ) else {
                errorMessage = "Couldn't load that match. Riot's API may be rate limiting."
                return
            }
            browsedMatch = MatchImportService.browsedMatch(
                detail: detail,
                viewedPuuid: puuid,
                context: modelContext
            )
        }
    }

    private func loadPage(reset: Bool) async {
        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }

        do {
            let page = try await PlayerProfileService.recentMatches(
                puuid: puuid,
                region: region,
                start: reset ? 0 : matches.count,
                count: pageSize
            )
            if reset { matches = page } else { matches.append(contentsOf: page) }
            // A short page means Riot has no more history to give.
            if page.count < pageSize { reachedEnd = true }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }

        isLoading = false
        isLoadingMore = false
    }
}
