import SwiftUI
import SwiftData

/// Head-to-head against another player's public record.
///
/// Built from the same pieces as the rest of the app rather than a stock
/// `Form`: cards on the grouped background, the versus banner from the match
/// detail's matchup tab, and the diverging comparison bars from the team tab.
/// A screen that reads as a settings sheet doesn't belong next to those.
struct FriendComparisonView: View {
    @Query(sort: \Match.timestamp, order: .reverse) private var myMatches: [Match]
    @Query private var accounts: [LinkedAccount]

    @State private var gameName = ""
    @State private var tagLine = ""
    @State private var platform: RiotPlatform = .oc1
    @State private var isLoading = false
    @State private var errorMessage: String?
    @State private var friendMatches: [OtherPlayerMatchSummary] = []
    @State private var friendDisplayName: String?
    @State private var friendTagline: String?
    @State private var friendProfile: OtherPlayerProfile?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @FocusState private var focusedField: Field?

    @ScaledMetric(relativeTo: .title3) private var avatarSize: CGFloat = 54
    @ScaledMetric(relativeTo: .caption) private var rankIconSize: CGFloat = 20
    @ScaledMetric(relativeTo: .subheadline) private var championSize: CGFloat = 36
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 8

    private enum Field { case name, tag }

    private var account: LinkedAccount? { accounts.first }
    private var myLeagueMatches: [Match] { myMatches.filter { $0.leagueStats != nil } }
    private var hasResult: Bool { !friendMatches.isEmpty }

    private var canCompare: Bool {
        !isLoading
            && !gameName.trimmingCharacters(in: .whitespaces).isEmpty
            && !tagLine.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var myAggregate: PlayerAggregateStats {
        guard !myLeagueMatches.isEmpty else { return .empty }
        let wins = myLeagueMatches.filter(\.win).count
        let kdas = myLeagueMatches.compactMap { $0.leagueStats?.kda }
        let topChampion = Dictionary(grouping: myLeagueMatches) { $0.leagueStats?.champion ?? "" }
            .max { $0.value.count < $1.value.count }?
            .key
        return PlayerAggregateStats(
            winRate: Double(wins) / Double(myLeagueMatches.count) * 100,
            averageKDA: kdas.reduce(0, +) / Double(max(kdas.count, 1)),
            gamesSampled: myLeagueMatches.count,
            topChampion: topChampion
        )
    }

    private var friendAggregate: PlayerAggregateStats {
        FriendComparisonService.aggregate(friendMatches)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: Theme.sectionSpacing) {
                searchCard

                if let errorMessage {
                    errorCard(errorMessage)
                }

                if hasResult {
                    versusCard
                    metricsCard
                    sampleNote
                } else if !isLoading {
                    emptyState
                }
            }
            .padding()
            .readableContentWidth()
        }
        .background(Color(.systemGroupedBackground))
        .scrollDismissesKeyboard(.interactively)
        .navigationTitle("Compare with a Friend")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Search

    private var searchCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Friend's Riot ID")
                .font(.headline)

            riotIDField

            HStack {
                Label("Server", systemImage: "globe")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                Spacer(minLength: 8)
                serverMenu
            }

            compareButton
        }
        .cardSurface()
    }

    /// The two fields are drawn as one control split by a "#", because that is
    /// how a Riot ID is written everywhere else — two separate rows labelled
    /// "Game name" and "Tagline (without #)" made the user reassemble it.
    @ViewBuilder
    private var riotIDField: some View {
        let name = TextField("Game name", text: $gameName)
            .focused($focusedField, equals: .name)
            .submitLabel(.next)
            .onSubmit { focusedField = .tag }

        let tag = HStack(spacing: 2) {
            Text("#").foregroundStyle(.tertiary)
            TextField("TAG", text: $tagLine)
                .focused($focusedField, equals: .tag)
                .submitLabel(.search)
                .onSubmit { if canCompare { compare() } }
        }

        Group {
            // Side by side reads as one identity; at accessibility sizes the
            // tag would be squeezed to a couple of characters, so it stacks.
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    name
                    Divider()
                    tag
                }
            } else {
                HStack(spacing: 6) {
                    name
                    Divider().frame(height: rankIconSize)
                    tag.frame(maxWidth: 110, alignment: .leading)
                }
            }
        }
        .font(.body)
        .textInputAutocapitalization(.never)
        .autocorrectionDisabled()
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    /// A menu rather than a `Picker` row, matching the game switcher in the
    /// navigation bar — the app already has one capsule-shaped chooser.
    private var serverMenu: some View {
        Menu {
            Picker("Server", selection: $platform) {
                ForEach(RiotPlatform.allCases) { option in
                    Text(option.displayName).tag(option)
                }
            }
        } label: {
            HStack(spacing: 5) {
                Text(platform.displayName)
                    .font(.subheadline.weight(.semibold))
                Image(systemName: "chevron.up.chevron.down")
                    .scaledFont(9, weight: .semibold)
            }
            .foregroundStyle(Theme.accent)
            .padding(.horizontal, 12)
            .padding(.vertical, 7)
            .background(Theme.accent.opacity(0.12))
            .clipShape(Capsule())
        }
    }

    private var compareButton: some View {
        Button {
            focusedField = nil
            compare()
        } label: {
            HStack(spacing: 8) {
                if isLoading {
                    ProgressView().controlSize(.small).tint(.white)
                } else {
                    Image(systemName: "arrow.left.arrow.right")
                }
                Text(isLoading ? "Comparing…" : "Compare")
                    .fontWeight(.semibold)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 12)
            .foregroundStyle(.white)
            .background(canCompare ? Theme.accent : Color.secondary.opacity(0.4))
            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        }
        .buttonStyle(PressableButtonStyle())
        .disabled(!canCompare)
    }

    private func errorCard(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "exclamationmark.triangle.fill")
                .foregroundStyle(Theme.loss)
            Text(message)
                .font(.subheadline)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(Theme.cardPadding)
        .background(Theme.loss.opacity(0.1))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .cardShadow()
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: "person.2.fill")
                .font(.largeTitle)
                .foregroundStyle(Theme.accent.opacity(0.5))
            Text("Enter a Riot ID to compare")
                .font(.subheadline.weight(.semibold))
            Text("Their win rate, average KDA and most-played champion, side by side with yours.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 32)
    }

    // MARK: - Versus banner

    /// The same arrangement as the match detail's matchup tab, so a comparison
    /// looks like a comparison wherever it appears in the app.
    private var versusCard: some View {
        let separator = Text("VS")
            .font(.caption2.weight(.black))
            .foregroundStyle(.secondary)

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    mySide(alignment: .leading)
                    separator
                    friendSide(alignment: .leading)
                }
            } else {
                HStack(spacing: 0) {
                    mySide(alignment: .leading)
                    separator.padding(.horizontal, 10)
                    friendSide(alignment: .trailing)
                }
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(
            LinearGradient(
                colors: [Theme.ally.opacity(0.14), .clear, Theme.enemy.opacity(0.14)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .cardShadow()
    }

    private func mySide(alignment: HorizontalAlignment) -> some View {
        combatant(
            name: account?.riotGameName ?? "You",
            subtitle: "You",
            iconID: account?.profileIconID,
            tier: account?.rankTier,
            division: account?.rankDivision,
            tint: Theme.ally,
            alignment: alignment
        )
    }

    private func friendSide(alignment: HorizontalAlignment) -> some View {
        combatant(
            name: friendDisplayName ?? "Friend",
            subtitle: friendTagline.map { "#\($0)" } ?? platform.displayName,
            iconID: friendProfile?.profileIconID,
            tier: friendProfile?.rankTier,
            division: friendProfile?.rankDivision,
            tint: Theme.enemy,
            alignment: alignment
        )
    }

    private func combatant(
        name: String,
        subtitle: String,
        iconID: Int?,
        tier: String?,
        division: String?,
        tint: Color,
        alignment: HorizontalAlignment
    ) -> some View {
        let trailing = alignment == .trailing

        let avatar = Group {
            if let iconID {
                ProfileIconView(profileIconID: iconID, size: avatarSize)
            } else {
                Circle()
                    .fill(tint.opacity(0.15))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay {
                        Image(systemName: "person.fill").foregroundStyle(tint)
                    }
            }
        }
        .overlay(Circle().strokeBorder(tint, lineWidth: 2))

        let identity = VStack(alignment: alignment, spacing: 3) {
            Text(name)
                .font(.subheadline.weight(.bold))
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(subtitle)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            if let tier {
                HStack(spacing: 4) {
                    RankIconView(tier: tier, size: rankIconSize)
                    Text(RankEmblemService.displayName(tier: tier, division: division ?? ""))
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .minimumScaleFactor(0.7)
                }
            }
        }

        return HStack(spacing: 10) {
            if !trailing { avatar }
            identity
            if trailing { avatar }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Metrics

    private var metricsCard: some View {
        VStack(alignment: .leading, spacing: 14) {
            comparisonBar(
                label: "Win rate",
                mine: myAggregate.winRate,
                theirs: friendAggregate.winRate,
                display: { "\(Int($0.rounded()))%" }
            )
            Divider()
            comparisonBar(
                label: "Avg KDA",
                mine: myAggregate.averageKDA,
                theirs: friendAggregate.averageKDA,
                display: { String(format: "%.2f", $0) }
            )
            Divider()
            championRow
        }
        .cardSurface()
    }

    /// Values on the outside, label in the middle, and a bar split by the two
    /// figures — the same read as the team comparison bars, so "who is ahead"
    /// is a glance rather than a subtraction.
    private func comparisonBar(
        label: String,
        mine: Double,
        theirs: Double,
        display: (Double) -> String
    ) -> some View {
        let total = max(mine + theirs, 0.0001)
        let myFraction = CGFloat(mine / total)
        let iLead = mine > theirs
        let theyLead = theirs > mine

        let mineText = Text(display(mine))
            .font(.subheadline.monospacedDigit().weight(iLead ? .bold : .regular))
            .foregroundStyle(Theme.ally)
        let theirsText = Text(display(theirs))
            .font(.subheadline.monospacedDigit().weight(theyLead ? .bold : .regular))
            .foregroundStyle(Theme.enemy)
        let title = Text(label)
            .font(.caption)
            .foregroundStyle(.secondary)

        return VStack(spacing: 5) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 2) {
                    title.frame(maxWidth: .infinity, alignment: .leading)
                    HStack { mineText; Spacer(minLength: 6); theirsText }
                }
            } else {
                HStack {
                    mineText
                    Spacer(minLength: 6)
                    title.lineLimit(1)
                    Spacer(minLength: 6)
                    theirsText
                }
            }

            GeometryReader { geo in
                HStack(spacing: 2) {
                    LinearGradient(
                        colors: [Theme.ally.opacity(0.7), Theme.ally],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                    .frame(width: max(geo.size.width * myFraction - 1, 0))
                    LinearGradient(
                        colors: [Theme.enemy, Theme.enemy.opacity(0.7)],
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                }
            }
            .frame(height: barHeight)
            .clipShape(Capsule())
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): you \(display(mine)), them \(display(theirs))")
    }

    /// Most-played champion is an identity, not a magnitude — two portraits
    /// say it immediately where two words needed reading.
    private var championRow: some View {
        let mine = myAggregate.topChampion
        let theirs = friendAggregate.topChampion

        return HStack {
            championBadge(mine, tint: Theme.ally, alignment: .leading)
            Text("Top champion")
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            championBadge(theirs, tint: Theme.enemy, alignment: .trailing)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Top champion: you \(mine ?? "none"), them \(theirs ?? "none")")
    }

    @ViewBuilder
    private func championBadge(_ champion: String?, tint: Color, alignment: HorizontalAlignment) -> some View {
        let trailing = alignment == .trailing
        HStack(spacing: 6) {
            if !trailing, let champion { ChampionIconView(championName: champion, size: championSize) }
            Text(champion ?? "—")
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(champion == nil ? Color.secondary : tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            if trailing, let champion { ChampionIconView(championName: champion, size: championSize) }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    /// The two samples are not the same size and are not gathered the same
    /// way. Burying that in a form footer made the numbers look more
    /// comparable than they are.
    private var sampleNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .foregroundStyle(.tertiary)
            Text("You: last \(myAggregate.gamesSampled) synced matches. Them: last \(friendAggregate.gamesSampled) matches, from the public Riot API only.")
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(.horizontal, 4)
    }

    // MARK: - Loading

    private func compare() {
        errorMessage = nil
        isLoading = true
        let name = gameName.trimmingCharacters(in: .whitespaces)
        let tag = tagLine.trimmingCharacters(in: .whitespaces)
        Task {
            do {
                let puuid = try await RiotAPIClient.shared.resolvePUUID(gameName: name, tagLine: tag, region: platform.region)
                friendMatches = try await PlayerProfileService.recentMatches(puuid: puuid, region: platform.region)
                friendDisplayName = name
                friendTagline = tag
                // Icon and rank are what make the banner read as a person
                // rather than a row of numbers, so they are worth the extra
                // call — and a failure there just leaves the placeholder.
                friendProfile = await PlayerProfileService.profile(puuid: puuid, platform: platform)
            } catch {
                errorMessage = (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
            }
            isLoading = false
        }
    }
}
