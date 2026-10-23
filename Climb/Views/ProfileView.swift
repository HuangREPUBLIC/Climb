import SwiftUI
import SwiftData

/// The Matches tab: who you are, how you've been playing and every synced game on one scroll, op.gg-style.
struct ProfileView: View {
    /// Owned by ContentView. Matches are pushed (not presented by item) so the coach pushes onto the same stack.
    @Binding var path: NavigationPath
    @Query private var accounts: [LinkedAccount]
    @Query(sort: \Match.timestamp, order: .reverse) private var allMatches: [Match]
    @AppStorage("selectedGame") private var selectedGame: Game = .league
    @State private var queueFilter: String?
    @State private var tagFilter: String?
    @State private var isLoadingOlder = false
    @State private var reachedEnd = false
    @State private var olderLoadFailed = false
    @State private var taggingMatch: Match?

    @Environment(\.modelContext) private var modelContext
    @ObservedObject private var keyPrompt = APIKeyPrompt.shared

    private var account: LinkedAccount? { accounts.first }
    /// Everything on this screen follows the game switcher.
    private var matches: [Match] { allMatches.filter { $0.game == selectedGame && $0.isOwnHistory } }
    private var filteredMatches: [Match] {
        matches.filter { match in
            (queueFilter.map { match.queueType == $0 } ?? true)
                && (tagFilter.map { match.tags.contains($0) } ?? true)
        }
    }
    private var tags: [String] { Set(matches.flatMap(\.tags)).sorted() }

    var body: some View {
        let filtered = filteredMatches
        ScrollView {
            VStack(spacing: 16) {
                VStack(spacing: 16) {
                    header
                    expiredKeyNotice
                    unpublishedMatchNotice
                    // The numbers follow the filters, so "Ranked Solo/Duo" answers "how am I doing in ranked".
                    if !filtered.isEmpty { ProfileSummaryStrip(matches: filtered) }
                }
                .padding(.horizontal)

                VStack(alignment: .leading, spacing: 0) {
                    if !matches.isEmpty { recentMatchesHeading(count: filtered.count) }
                    let queues = matches.queuesByPlays
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
        .screen("Matches")
        .refreshable { try? await MatchImportService.syncLinkedAccount(context: modelContext) }
        .navigationDestination(for: Match.self) { match in
            MatchDetailView(match: match)
        }
        .navigationDestination(for: MatchesRoute.self) { route in
            switch route {
            case .savedGames: SavedGamesView(path: $path)
            case .settings: SettingsView()
            }
        }
        .toolbar {
            GameFilterPicker(selection: $selectedGame, availableGames: Set(allMatches.map(\.game)))
            // One group, so the two share a glass capsule.
            ToolbarItemGroup(placement: .primaryAction) {
                NavigationLink(value: MatchesRoute.savedGames) {
                    Image(systemName: "bookmark")
                }
                .accessibilityLabel("Saved games")
                NavigationLink(value: MatchesRoute.settings) {
                    Image(systemName: "gearshape")
                }
                .accessibilityLabel("Settings")
            }
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
            if let account {
                BannerTitle(text: account.riotID)
                RankChip(tier: account.rankTier, division: account.rankDivision, leaguePoints: account.leaguePoints)
            }
        }
    }

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

    /// The key sheet opens by itself only once; after Cancel this says why nothing new is syncing.
    @ViewBuilder
    private var expiredKeyNotice: some View {
        if keyPrompt.riotKeyRejected {
            Button {
                // A prompt raised under another sheet never showed but left the flag set; toggle to re-fire.
                keyPrompt.isPresented = false
                Task { @MainActor in keyPrompt.isPresented = true }
            } label: {
                HStack(spacing: 10) {
                    Image(systemName: "key.slash")
                        .foregroundStyle(Theme.orange)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Riot API key expired")
                            .font(.subheadline.weight(.semibold))
                        Text("Showing games synced earlier. Paste today's key to sync new ones.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Spacer(minLength: 4)
                    Text("Update")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(Theme.accent)
                }
                .foregroundStyle(.primary)
                .padding(Theme.cardPadding)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            }
            .buttonStyle(PressableButtonStyle())
        }
    }

    /// Riot's match API can lag the account by hours (event queues especially); saying so keeps a stale newest
    /// match from reading as broken. Uses Summoner-V4's `revisionDate`, already fetched on every sync.
    @ViewBuilder
    private var unpublishedMatchNotice: some View {
        // 3h of slack: a long game plus start-to-revision lag is ~2h, and a false hint is worse than none.
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
            .background(Color.orange.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
            .accessibilityElement(children: .combine)
        }
    }

    /// Scrolling to the end loads the next page; the button is for retries and for filtered lists, where
    /// the end isn't a request for more (a page costs ~40 of a personal key's 100 requests per two minutes).
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
                olderLoadFailed = true
            }
            isLoadingOlder = false
        }
    }
}

/// The Matches top bar's screens, pushed by value so a saved game opened from them can still push the coach.
enum MatchesRoute: Hashable {
    case savedGames, settings
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
            .screen("Tags")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}
