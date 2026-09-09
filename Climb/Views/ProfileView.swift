import SwiftUI
import SwiftData

struct ProfileView: View {
    @Query private var accounts: [LinkedAccount]
    @Query(sort: \Match.timestamp, order: .reverse) private var allMatches: [Match]
    @State private var showingLinkAccount = false
    @AppStorage("selectedGameFilter") private var selectedGameRaw = GameFilter.league.rawValue

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 82
    @ScaledMetric(relativeTo: .caption) private var rankIconSize: CGFloat = 26
    @ScaledMetric(relativeTo: .title3) private var summaryDividerHeight: CGFloat = 40

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
            }
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingLinkAccount = true
                } label: {
                    Image(systemName: "arrow.triangle.2.circlepath")
                }
            }
        }
        .sheet(isPresented: $showingLinkAccount) {
            LinkAccountView()
        }
    }

    // MARK: - Header

    /// Everything sits inside the banner rather than straddling its edge —
    /// an avatar half-on/half-off the gradient seam reads as cramped, and the
    /// hard colour boundary it created was the most jarring edge on the screen.
    /// The player's most-played champion, used as the banner's backdrop.
    ///
    /// A flat accent gradient said nothing about the person it belonged to.
    /// Splash art of whoever they actually play does — and it gives the glass
    /// chip something to refract, since glass over a solid fill is just a
    /// translucent rectangle.
    private var bannerChampion: String? {
        Dictionary(grouping: leagueMatches) { $0.leagueStats?.champion ?? "" }
            .filter { !$0.key.isEmpty }
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

            // Splash art puts the champion off to one side and can be bright
            // anywhere, so the scrim carries the text contrast on its own
            // rather than trusting the art to be dark where the text lands.
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

    /// Used before any match has been synced, and whenever the art fails to
    /// load — the banner should never collapse to a blank rectangle.
    private var accentFallback: some View {
        LinearGradient(
            colors: [Theme.accent, Theme.accent.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var avatarView: some View {
        Group {
            if let account, let iconID = account.profileIconID {
                ProfileIconView(profileIconID: iconID, size: avatarSize)
            } else {
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    }
            }
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
        // Level rides on the portrait the way the game client draws it, which
        // frees the row below for the one fact worth a chip of its own.
        .overlay(alignment: .bottom) {
            if let level = account?.summonerLevel {
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
        if let account {
            VStack(spacing: 12) {
                Text(account.riotID)
                    .font(.title2.bold())
                    .foregroundStyle(.white)
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                    .minimumScaleFactor(0.5)
                    .frame(maxWidth: .infinity)
                    .shadow(color: .black.opacity(0.45), radius: 6, y: 1)

                rankChip(for: account)
            }
            .frame(maxWidth: .infinity)
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

    /// One chip now that the level lives on the portrait. Liquid Glass rather
    /// than a white wash: it picks up the art behind it instead of flattening
    /// a rectangle over it.
    private func rankChip(for account: LinkedAccount) -> some View {
        HStack(spacing: 6) {
            if let tier = account.rankTier, let division = account.rankDivision {
                RankIconView(tier: tier, size: rankIconSize)
                Text(RankEmblemService.displayName(tier: tier, division: division))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                if let lp = account.leaguePoints {
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
        // Only win rate is colour-coded, because only it carries meaning
        // (above or below even). The others were decorative tints.
        let columns = [
            statColumn(icon: "gamecontroller.fill", tint: .secondary, label: "Matches", value: "\(matches.count)"),
            statColumn(icon: "percent", tint: winRate >= 50 ? Theme.win : Theme.loss, label: "Win rate", value: "\(Int(winRate.rounded()))%"),
            statColumn(icon: "trophy.fill", tint: .yellow, label: "Record", value: "\(wins)-\(leagueMatches.count - wins)")
        ]

        // Three columns become three rows at accessibility sizes: a third of
        // the width can't hold "Win rate" and its number without truncating.
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
            Image(systemName: icon)
                .font(.caption)
                .foregroundStyle(tint)
            Text(value).font(.title3.bold()).monospacedDigit()
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
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
