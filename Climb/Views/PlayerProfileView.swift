import SwiftUI
import SwiftData

struct OtherPlayerProfile {
    let summoner: RiotSummonerResponse?
    let solo: RiotLeagueEntry?
}

/// Another player's page: your own banner and summary layout, their paged history, and a comparison with you.
struct PlayerProfileView: View {
    /// Nil when opened from the Following list; resolved from the Riot ID then.
    let puuid: String?
    let riotIdGameName: String
    let riotIdTagline: String
    let region: RiotRegion
    var platform: RiotPlatform?

    @State private var resolvedPUUID: String?
    @State private var profile: OtherPlayerProfile?
    @State private var matches: [Match] = []
    /// Next page's start in Riot's id list, not `matches.count`: a game that failed to load still used its slot.
    @State private var nextStart = 0
    @State private var isLoading = true
    @State private var isLoadingMore = false
    @State private var reachedEnd = false
    @State private var errorMessage: String?
    @State private var browsedMatch: Match?

    @Environment(\.modelContext) private var modelContext
    @Query private var accounts: [LinkedAccount]
    @Query(sort: \Match.timestamp, order: .reverse) private var allMatches: [Match]
    @Query private var savedPlayers: [SavedPlayer]

    private let pageSize = 15

    private var followed: SavedPlayer? {
        let key = SavedPlayer.key(gameName: riotIdGameName, tagLine: riotIdTagline)
        return savedPlayers.first { $0.key == key }
    }
    private var isYou: Bool {
        accounts.first.map { LinkedAccount.identity(gameName: $0.riotGameName, tagLine: $0.riotTagline) }
            == LinkedAccount.identity(gameName: riotIdGameName, tagLine: riotIdTagline)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                header
                if !matches.isEmpty {
                    ProfileStatsSection(matches: matches)
                    if !isYou { compareCard }
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
            .padding(.bottom)
            .readableContentWidth()
        }
        .screen("\(riotIdGameName)#\(riotIdTagline)")
        .navigationDestination(item: $browsedMatch) { match in
            MatchDetailView(match: match)
        }
        .toolbar {
            if !isYou {
                ToolbarItem(placement: .primaryAction) {
                    followButton
                }
            }
        }
        .sensoryFeedback(.selection, trigger: followed == nil)
        .task {
            if resolvedPUUID == nil {
                do {
                    if let puuid {
                        resolvedPUUID = puuid
                    } else {
                        resolvedPUUID = try await RiotAPIClient.shared.resolvePUUID(
                            gameName: riotIdGameName,
                            tagLine: riotIdTagline,
                            region: region
                        )
                    }
                } catch {
                    errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
                    isLoading = false
                    return
                }
            }
            if let platform, profile == nil, let resolvedPUUID {
                let client = RiotAPIClient.shared
                profile = OtherPlayerProfile(
                    summoner: try? await client.fetchSummoner(puuid: resolvedPUUID, platform: platform),
                    solo: await client.soloRank(puuid: resolvedPUUID, platform: platform)
                )
            }
            await loadPage(reset: true)
        }
    }

    // MARK: - Header

    private var header: some View {
        ProfileBanner(
            profileIconID: profile?.summoner?.profileIconId,
            level: profile?.summoner?.summonerLevel,
            matches: matches
        ) {
            BannerTitle(text: "\(riotIdGameName)#\(riotIdTagline)")
            if let profile {
                RankChip(tier: profile.solo?.tier, division: profile.solo?.rank, leaguePoints: profile.solo?.leaguePoints)
            }
        }
    }

    // MARK: - Compare

    /// Their loaded games against your last 20.
    private var compareCard: some View {
        let mine = FriendComparisonService.aggregate(Array(allMatches.filter { $0.isOwnHistory && $0.leagueStats != nil }.prefix(20)))
        let theirs = FriendComparisonService.aggregate(matches)

        return VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("You").foregroundStyle(Theme.ally)
                Spacer()
                Text("vs").foregroundStyle(.secondary)
                Spacer()
                Text(riotIdGameName).foregroundStyle(Theme.enemy).lineLimit(1)
            }
            .font(.subheadline.weight(.semibold))

            comparisonBar("Win rate", mine: mine.winRate, theirs: theirs.winRate) { "\(Int($0.rounded()))%" }
            comparisonBar("KDA", mine: mine.kda, theirs: theirs.kda) { String(format: "%.2f", $0) }

            HStack {
                topChampion(mine.topChampion)
                Spacer()
                Text("Most played").font(.caption).foregroundStyle(.secondary)
                Spacer()
                topChampion(theirs.topChampion)
            }
        }
        .cardSurface()
    }

    private func comparisonBar(_ label: String, mine: Double, theirs: Double, display: (Double) -> String) -> some View {
        let fraction = CGFloat(mine / max(mine + theirs, 0.0001))
        return VStack(spacing: 5) {
            HStack {
                Text(display(mine))
                    .fontWeight(mine > theirs ? .bold : .regular)
                    .foregroundStyle(Theme.ally)
                Spacer(minLength: 6)
                Text(label).font(.caption).foregroundStyle(.secondary)
                Spacer(minLength: 6)
                Text(display(theirs))
                    .fontWeight(theirs > mine ? .bold : .regular)
                    .foregroundStyle(Theme.enemy)
            }
            .font(.subheadline.monospacedDigit())
            GeometryReader { geo in
                HStack(spacing: 2) {
                    Theme.ally.frame(width: max(geo.size.width * fraction - 1, 0))
                    Theme.enemy
                }
            }
            .frame(height: 6)
            .clipShape(Capsule())
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func topChampion(_ name: String?) -> some View {
        if let name {
            ChampionIconView(championName: name, size: 32)
        } else {
            Color.clear.frame(width: 32, height: 32)
        }
    }

    /// Words, not a bare toolbar icon; prominent as an invitation, plain glass once followed.
    @ViewBuilder
    private var followButton: some View {
        if followed == nil {
            Button("Follow", action: toggleFollow)
                .buttonStyle(.glassProminent)
        } else {
            Button("Following", action: toggleFollow)
                .accessibilityHint("Unfollows this player")
        }
    }

    private func toggleFollow() {
        if let followed {
            modelContext.delete(followed)
        } else {
            modelContext.insert(SavedPlayer(
                gameName: riotIdGameName,
                tagLine: riotIdTagline,
                platform: (platform ?? accounts.first.flatMap { RiotPlatform(rawValue: $0.platform) })?.rawValue ?? ""
            ))
        }
    }

    // MARK: - Matches

    private var matchesCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Match history").font(.headline)

            MatchCardList(matches: matches, open: { browsedMatch = $0 })

            if !reachedEnd {
                Button {
                    Task { await loadPage(reset: false) }
                } label: {
                    HStack(spacing: 6) {
                        if isLoadingMore { ProgressView().controlSize(.small) }
                        Text(isLoadingMore ? "Loading…" : "Load more")
                    }
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(Theme.accent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                }
                .buttonStyle(PressableButtonStyle())
                .disabled(isLoadingMore)
                .onScrollVisibilityChange(threshold: 0.5) { visible in
                    if visible, !isLoadingMore { Task { await loadPage(reset: false) } }
                }
            }
        }
    }

    // MARK: - Loading

    /// Each game is fetched once and cached as a `Match`, so a revisit costs one id-list request.
    private func loadPage(reset: Bool) async {
        guard let puuid = resolvedPUUID else { return }
        if reset {
            isLoading = true
        } else {
            isLoadingMore = true
        }
        defer {
            isLoading = false
            isLoadingMore = false
        }

        do {
            let pageStart = reset ? 0 : nextStart
            let ids = try await RiotAPIClient.shared.fetchRecentMatchIDs(puuid: puuid, region: region, start: pageStart, count: pageSize)
            nextStart = pageStart + ids.count
            if ids.count < pageSize { reachedEnd = true }

            var page: [Match] = []
            for (index, matchID) in ids.enumerated() {
                do {
                    if let match = try await MatchImportService.browsedMatch(
                        matchID: matchID,
                        viewedPuuid: puuid,
                        region: region,
                        context: modelContext
                    ), !page.contains(match), reset || !matches.contains(match) {
                        // Riot's list shifts when a game finishes between pages; never list a game twice.
                        page.append(match)
                    }
                } catch RiotAPIError.rateLimited {
                    // Keep what loaded; "Load more" resumes at this game.
                    nextStart = pageStart + index
                    reachedEnd = false
                    if page.isEmpty {
                        errorMessage = RiotAPIError.rateLimited.errorDescription
                    }
                    break
                } catch {
                    continue
                }
            }
            // A reset that came back empty (rate limited) keeps what was shown.
            if reset, !page.isEmpty || matches.isEmpty { matches = page } else if !reset { matches += page }
        } catch {
            errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
        }
    }
}
