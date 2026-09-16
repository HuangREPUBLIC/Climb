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

    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 76
    @ScaledMetric(relativeTo: .caption) private var rankIconSize: CGFloat = 26
    @ScaledMetric(relativeTo: .title3) private var summaryDividerHeight: CGFloat = 40
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
        VStack(spacing: 12) {
            avatarView
            identityBlock
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background { bannerBackdrop }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
    }

    @ViewBuilder
    private var bannerBackdrop: some View {
        ZStack {
            if let bannerChampion, let url = DataDragonService.shared.splashArtURL(for: bannerChampion) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        accentFallback
                    }
                }
            } else {
                accentFallback
            }

            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.28), location: 0.45),
                    .init(color: .black.opacity(0.70), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Their history loads after the view appears, so the banner has no
    /// champion to show at first — the accent keeps it from flashing empty.
    private var accentFallback: some View {
        LinearGradient(
            colors: [Theme.accent, Theme.accent.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var avatarView: some View {
        Group {
            if let iconID = profile?.profileIconID {
                ProfileIconView(profileIconID: iconID, size: avatarSize)
            } else {
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.title)
                            .foregroundStyle(.white)
                    }
            }
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
        .overlay(alignment: .bottom) {
            if let level = profile?.summonerLevel {
                Text("\(level)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                    .offset(y: 7)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }

    @ViewBuilder
    private var identityBlock: some View {
        VStack(spacing: 12) {
            Text("\(riotIdGameName)#\(riotIdTagline)")
                .font(.title2.bold())
                .foregroundStyle(.white)
                .multilineTextAlignment(.center)
                .lineLimit(2)
                .minimumScaleFactor(0.5)
                .frame(maxWidth: .infinity)
                .shadow(color: .black.opacity(0.45), radius: 6, y: 1)

            if profile != nil {
                rankChip
            }
        }
        .frame(maxWidth: .infinity)
    }

    private var rankChip: some View {
        HStack(spacing: 6) {
            if let tier = profile?.rankTier, let division = profile?.rankDivision {
                RankIconView(tier: tier, size: rankIconSize)
                Text(RankEmblemService.displayName(tier: tier, division: division))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                if let lp = profile?.leaguePoints {
                    Text("\u{00B7} \(lp) LP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Unranked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect()
    }


    // MARK: - Summary

    private var summaryCard: some View {
        let wins = matches.filter(\.win).count
        let winRate = matches.isEmpty ? 0 : Double(wins) / Double(matches.count) * 100
        let avgKDA = matches.isEmpty ? 0 : matches.map(kdaValue).reduce(0, +) / Double(matches.count)

        let columns = [
            statColumn(icon: "gamecontroller.fill", tint: .secondary, label: "Loaded", value: "\(matches.count)"),
            statColumn(icon: "percent", tint: winRate >= 50 ? Theme.win : Theme.loss, label: "Win rate", value: "\(Int(winRate.rounded()))%"),
            statColumn(icon: "bolt.fill", tint: .secondary, label: "Avg KDA", value: String(format: "%.2f", avgKDA))
        ]

        // Three columns become three rows at accessibility sizes — see
        // ProfileView, which uses the same summary card.
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        if index > 0 { Divider() }
                        column
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(columns.enumerated()), id: \.offset) { index, column in
                        if index > 0 { Divider().frame(height: summaryDividerHeight) }
                        column
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .cardShadow()
    }

    private func statColumn(icon: String, tint: Color, label: String, value: String) -> some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.caption).foregroundStyle(tint)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
