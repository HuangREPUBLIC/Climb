import SwiftUI
import SwiftData

/// The Matches tab (战绩): who you are, how you've been playing, and every
/// synced game on one scroll, the way 掌盟 lays it out — rather than a profile
/// previewing five games and a second tab listing the same ones again.
struct ProfileView: View {
    /// The Matches stack's path, owned by ContentView. A match is pushed onto
    /// it rather than presented by item, so links inside the match screen
    /// (the AI coach) push onto the same stack.
    @Binding var path: NavigationPath
    @Query private var accounts: [LinkedAccount]
    @Query(sort: \Match.timestamp, order: .reverse) private var allMatches: [Match]
    @AppStorage("selectedGame") private var selectedGame: Game = .league
    @State private var showingLinkAccount = false
    @State private var queueFilter: String?
    @State private var tagFilter: String?
    @State private var isLoadingOlder = false
    @State private var reachedEnd = false
    @State private var olderLoadFailed = false
    @State private var taggingMatch: Match?

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
        let filtered = filteredMatches
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 16) {
                    header
                    unpublishedMatchNotice
                    // The numbers follow the filters, so picking "Ranked
                    // Solo/Duo" answers "how am I doing in ranked".
                    if !filtered.isEmpty { ProfileStatsSection(matches: filtered) }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 0) {
                    if !matches.isEmpty { recentMatchesHeading(count: filtered.count) }
                    if queues.count > 1 {
                        TagFilterBar(tags: queues, selection: $queueFilter)
                    }
                    if !tags.isEmpty {
                        TagFilterBar(tags: tags, selection: $tagFilter)
                    }
                }

                Group {
                    if matches.isEmpty {
                        ContentUnavailableView(
                            "No matches yet",
                            systemImage: "gamecontroller",
                            description: Text("Riot has no recent games for this account. Pull down to check again after you play.")
                        )
                    } else if filtered.isEmpty {
                        ContentUnavailableView(
                            "No matches for this filter",
                            systemImage: "line.3.horizontal.decrease",
                            description: Text("Tap the selected filter again to clear it.")
                        )
                    } else {
                        MatchCardList(
                            matches: filtered,
                            open: { path.append($0) },
                            editTags: { taggingMatch = $0 }
                        )
                    }
                    if selectedGame == .league, !matches.isEmpty {
                        loadOlderButton
                    }
                }
                .padding(.horizontal)
            }
            .padding(.bottom)
            .readableContentWidth()
        }
        .background(Theme.background)
        // The standard system gesture for "get the latest data".
        .refreshable { try? await MatchImportService.syncLinkedAccount(context: modelContext) }
        .navigationTitle("Matches")
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
                .accessibilityLabel("Sync or switch Riot account")
            }
        }
        .sheet(isPresented: $showingLinkAccount) {
            LinkAccountView()
        }
        .sheet(item: $taggingMatch) { match in
            TagSheet(match: match, vocabulary: ReflectionTag.vocabulary(for: match.game, usedIn: allMatches))
        }
        .onChange(of: selectedGame) {
            queueFilter = nil
            tagFilter = nil
        }
    }

    // MARK: - Header

    private var header: some View {
        ProfileBanner(
            profileIconID: account?.profileIconID,
            level: account?.summonerLevel,
            matches: matches
        ) {
            // ContentView shows onboarding until there is an account.
            if let account {
                BannerTitle(text: account.riotID)
                RankChip(tier: account.rankTier, division: account.rankDivision, leaguePoints: account.leaguePoints)
            }
        }
    }

    /// Names the list, and says how many games the filters leave.
    private func recentMatchesHeading(count: Int) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            Text("Recent Matches")
                .font(.title3.bold())
            Text("\(count)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(Theme.accent)
                .padding(.horizontal, 8)
                .padding(.vertical, 2)
                .background(Theme.accent.opacity(0.12), in: Capsule())
        }
        .padding(.horizontal)
        .padding(.bottom, 4)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
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

    /// Scrolling to the end of the list loads the next page; the button is
    /// for a retry, and for a filtered list, where reaching the end isn't a
    /// request for more (each page costs ~40 of a personal key's 100 requests
    /// per two minutes).
    private var loadOlderButton: some View {
        Button {
            loadOlder()
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
        .onScrollVisibilityChange(threshold: 0.5) { visible in
            // A failure waits for a tap, so a rate limit can't loop.
            if visible, !reachedEnd, !olderLoadFailed, queueFilter == nil, tagFilter == nil { loadOlder() }
        }
    }

    private func loadOlder() {
        guard !isLoadingOlder else { return }
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
    }
}

/// Tags for one match from the long-press menu, without opening the match.
private struct TagSheet: View {
    @Bindable var match: Match
    let vocabulary: [String]

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            ScrollView {
                TagEditor(tags: $match.tags, vocabulary: vocabulary)
                    .padding()
            }
            .background(Theme.background)
            .navigationTitle("Tags")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
