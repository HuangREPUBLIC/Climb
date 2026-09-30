import SwiftUI
import SwiftData

/// Another player's page: the same banner and summary as your own, their
/// history with paging, and how they compare with you — the separate compare
/// screen this replaced only ever showed that last part.
struct PlayerProfileView: View {
    /// Nil when opened from a saved friend; resolved from the Riot ID then.
    let puuid: String?
    let riotIdGameName: String
    let riotIdTagline: String
    let region: RiotRegion
    var platform: RiotPlatform?

    @State private var resolvedPUUID: String?
    @State private var profile: OtherPlayerProfile?
    /// Cached `Match` copies of their games, so they list with the same rows
    /// as your own history and open without another request.
    @State private var matches: [Match] = []
    /// Where the next page starts in Riot's id list — not `matches.count`,
    /// since a game that failed to load still used up its slot.
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

    private var savedEntry: SavedPlayer? {
        let key = SavedPlayer.key(gameName: riotIdGameName, tagLine: riotIdTagline)
        return savedPlayers.first { $0.key == key }
    }
    private var isYou: Bool {
        accounts.first.map { SavedPlayer.key(gameName: $0.riotGameName, tagLine: $0.riotTagline) }
            == SavedPlayer.key(gameName: riotIdGameName, tagLine: riotIdTagline)
    }


    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 20) {
                    header
                    if !matches.isEmpty {
                        if !isYou, accounts.first != nil { compareCard }
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
        .background(Theme.background)
        .navigationTitle("\(riotIdGameName)#\(riotIdTagline)")
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(item: $browsedMatch) { match in
            MatchDetailView(match: match)
        }
        .toolbar {
            if !isYou {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        toggleSaved()
                    } label: {
                        Image(systemName: savedEntry == nil ? "star" : "star.fill")
                    }
                    .accessibilityLabel(savedEntry == nil ? "Add to Friends" : "Remove from Friends")
                }
            }
        }
        .sensoryFeedback(.selection, trigger: savedEntry == nil)
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
                profile = await PlayerProfileService.profile(puuid: resolvedPUUID, platform: platform)
            }
            await loadPage(reset: true)
        }
    }

    // MARK: - Header

    /// Same card as your own profile — see ProfileView.
    private var header: some View {
        ProfileBanner(
            profileIconID: profile?.profileIconID,
            level: profile?.summonerLevel,
            matches: matches
        ) {
            BannerTitle(text: "\(riotIdGameName)#\(riotIdTagline)")
            if let profile {
                RankChip(tier: profile.rankTier, division: profile.rankDivision, leaguePoints: profile.leaguePoints)
            }
        } footer: {
            if !matches.isEmpty { StatSummaryCard(matches: matches, embedded: true) }
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

    /// Values outside, label between, and a bar split by the two — "who is
    /// ahead" is a glance rather than a subtraction.
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

    private func toggleSaved() {
        if let savedEntry {
            modelContext.delete(savedEntry)
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
            }
        }
    }

    // MARK: - Loading

    /// Each game is fetched once and kept as a cached `Match`, so the row can
    /// show the full build and the detail screen opens instantly. A revisit
    /// costs one id-list request.
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
            // A short page means Riot has no more history to give.
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
                        // Riot's list shifts when they finish a game between
                        // pages; the same game must not list twice.
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
