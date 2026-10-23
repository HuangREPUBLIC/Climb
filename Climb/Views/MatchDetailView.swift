import SwiftUI
import SwiftData

struct MatchDetailView: View {
    @Bindable var match: Match
    @Query private var accounts: [LinkedAccount]
    /// Only for the tag vocabulary — a tag invented on one match should be
    /// offered as a chip on the next one instead of retyped.
    @Query private var allMatches: [Match]

    /// The scoreboard first — it is what a match screen is opened for — and
    /// the player's own stat card one tab over instead of a screen above it.
    private enum DetailTab: String, CaseIterable, Identifiable {
        case players = "Players"
        case team = "Team"
        case matchup = "Matchup"
        case you = "You"
        var id: String { rawValue }
    }

    @State private var selectedTab: DetailTab = .players

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// The splash header is sized from its text, not the other way round —
    /// this is the floor it starts from at the default text size.
    @ScaledMetric(relativeTo: .title) private var headerMinHeight: CGFloat = 220
    @ScaledMetric(relativeTo: .caption2) private var participationRingSize: CGFloat = 58
    @ScaledMetric(relativeTo: .caption2) private var detailItemSize: CGFloat = 36
    @ScaledMetric(relativeTo: .body) private var notesMinHeight: CGFloat = 100
    /// Stat tiles reflow to fewer columns rather than truncating their
    /// numbers — "12,450" clipped to "12,4…" is worse than a taller card.
    @ScaledMetric(relativeTo: .subheadline) private var statTileMinWidth: CGFloat = 92
    @ScaledMetric(relativeTo: .caption) private var rateStatMinWidth: CGFloat = 62
    @ScaledMetric(relativeTo: .caption2) private var statGlyphSize: CGFloat = 24

    private var statTileColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.adaptive(minimum: statTileMinWidth), spacing: 10)]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    }

    /// The match's own server first: a game browsed from a Korean player's
    /// profile has to look its players up in Korea, not on your server.
    private var platform: RiotPlatform? {
        match.platform ?? RiotPlatform(rawValue: accounts.first?.platform ?? "")
    }

    private var region: RiotRegion? { platform?.region }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header
                    .overlay(alignment: .topTrailing) {
                        if match.isOwnHistory { coachButton }
                    }

                VStack(alignment: .leading, spacing: 16) {
                    if let stats = match.tftStats {
                        tftStatsSection(stats)
                    }

                    if !match.participants.isEmpty {
                        if match.isOwnHistory, match.leagueStats != nil {
                            MatchReviewCard(match: match, allMatches: allMatches)
                        }
                        tabPicker
                        tabContent
                    } else if let stats = match.leagueStats {
                        leagueStatsSection(stats)
                    }

                    reflectionSection
                }
                .padding()
            }
            .readableContentWidth()
        }
        .screen(match.leagueStats?.champion ?? (match.tftStats != nil ? "Teamfight Tactics" : match.game.shortName))
        .navigationDestination(for: CoachRoute.self) { route in
            CoachChatView(match: route.match)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(match.isSaved ? "Unsave game" : "Save game", systemImage: match.isSaved ? "bookmark.fill" : "bookmark") {
                    match.isSaved.toggle()
                }
                .contentTransition(.symbolEffect(.replace))
            }
        }
        .sensoryFeedback(.selection, trigger: match.isSaved)
    }

    /// On the header rather than at the foot of a long page, so the coach is
    /// one tap from the moment the match opens.
    private var coachButton: some View {
        NavigationLink(value: CoachRoute(match: match)) {
            Label("AI Review", systemImage: "sparkles")
                .font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.glass)
        .padding(12)
    }

    @ViewBuilder
    private var header: some View {
        if let stats = match.leagueStats, let url = DataDragonService.shared.splashArtURL(for: stats.champion) {
            // The art is a background rather than a fixed-height layer the
            // text sits on top of: at large text sizes the headline needs more
            // than 220pt, and the art has to follow it instead of clipping it.
            headerContent(stats)
                .padding(18)
                .frame(maxWidth: .infinity, minHeight: headerMinHeight, alignment: .bottomLeading)
                .background {
                    ZStack {
                        AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: {
                            Rectangle().fill(.secondary.opacity(0.2))
                        }

                        // Scrim weighted to the lower half where the text sits,
                        // so the outcome and metadata clear contrast on any
                        // champion art.
                        LinearGradient(
                            stops: [
                                .init(color: .clear, location: 0),
                                .init(color: .black.opacity(0.35), location: 0.45),
                                .init(color: .black.opacity(0.88), location: 1)
                            ],
                            startPoint: .top,
                            endPoint: .bottom
                        )
                    }
                }
                .clipped()
        } else if let stats = match.tftStats {
            VStack(spacing: 4) {
                Text("#\(stats.placement)")
                    .scaledFont(56, relativeTo: .largeTitle, weight: .bold)
                    .foregroundStyle(match.win ? Theme.win : Theme.loss)
                Text("Teamfight Tactics")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(Theme.surface)
        }
    }

    /// Outcome headline with the score beside it, then queue and timing
    /// underneath — the reference app's hero layout. The score sits in a
    /// filled chip because bare tinted text over splash art fails contrast at
    /// low scores (grey on dark = invisible).
    @ViewBuilder
    private func headerContent(_ stats: LeagueStats) -> some View {
        let headline = Text(match.win ? "VICTORY" : "DEFEAT")
            .scaledFont(32, relativeTo: .largeTitle, weight: .heavy)
            .foregroundStyle(match.win ? Theme.win : Theme.loss)
            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)

        let badge = Group {
            if let multiKill = stats.multiKillLabel {
                Text(multiKill)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.yellow.opacity(0.9), in: Capsule())
                    .foregroundStyle(.black)
            }
        }

        let outcome = VStack(alignment: .leading, spacing: 10) {
            // Baseline-aligned beside the headline, and only wrapping onto a
            // second line once "VICTORY" alone fills the width.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(FlowLayout(spacing: 12))
                : AnyLayout(HStackLayout(alignment: .firstTextBaseline, spacing: 12))
            layout { headline; badge }

            // One separator per line, per the metadata rule: queue and
            // duration ride together, the date stands alone.
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(match.queueType)
                        .font(.subheadline.weight(.semibold))
                    Text("·").foregroundStyle(.white.opacity(0.45))
                    Text(durationString)
                        .font(.subheadline.monospacedDigit())
                }
                .foregroundStyle(.white)

                Text(match.timestamp.formatted(date: .abbreviated, time: .shortened))
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.7))
            }
        }

        let score = PerformanceScore.compute(for: match)

        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 12) {
                outcome
                if let score { scoreChip(score) }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        } else {
            HStack(alignment: .bottom) {
                outcome
                Spacer(minLength: 12)
                if let score { scoreChip(score) }
            }
        }
    }

    /// Riot has no official per-match rating, so this is our own weighted
    /// estimate — labelled as such rather than passed off as a real stat.
    /// Solid fill (not tinted text) so it stays legible over any splash art.
    private func scoreChip(_ score: Double) -> some View {
        VStack(spacing: -2) {
            Text(String(format: "%.1f", score))
                .scaledFont(30, relativeTo: .largeTitle, weight: .heavy, monospacedDigit: true)
                .foregroundStyle(.white)
            Text("RATING")
                .scaledFont(8, weight: .bold)
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(PerformanceScore.color(for: score), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    private func leagueStatsSection(_ stats: LeagueStats) -> some View {
        SectionCard {
            // KDA headline with the kill/death/assist split colour-coded
            // and kill participation shown as a ring, rather than three
            // more identical grey rows.
            HStack(alignment: .center, spacing: 16) {
                VStack(alignment: .leading, spacing: 6) {
                    KDAColumns(stats: stats)
                    Text(stats.role)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer()

                if let me = match.focusParticipant, let share = match.killShare(of: me) {
                    participationRing(Int((share * 100).rounded()))
                }
            }

            Divider()

            // One neutral tile treatment instead of six different tints —
            // the colours were decorative, not semantic, and made the card
            // read as a sticker sheet.
            LazyVGrid(columns: statTileColumns, spacing: 10) {
                // Tints are semantic, not decorative: gold is gold, damage
                // dealt is red, damage taken is a shield blue, healing is
                // pink. Only the glyph is tinted — colouring the numbers too
                // is what turned an earlier version of this card into a
                // sticker sheet.
                iconStat("Minions", "\(stats.creepScore)", icon: "leaf.fill", tint: .green)
                iconStat("Gold", stats.goldEarned.formatted(), icon: "dollarsign.circle.fill", tint: .yellow)
                iconStat("Vision", "\(stats.visionScore)", icon: "eye.fill", tint: .cyan)
                iconStat("Dealt", stats.damageDealtToChampions.formatted(), icon: "burst.fill", tint: .red)
                iconStat("Taken", stats.damageTaken.formatted(), icon: "shield.fill", tint: .blue)
                iconStat("Healed", match.focusParticipant?.totalHeal.formatted() ?? "0", icon: "cross.case.fill", tint: .pink)
            }

            // Per-minute rates and standout moments, folded in here rather
            // than repeated in a separate card.
            let minutes = match.minutes
            let rates = Group {
                MiniStat(value: String(format: "%.0f", Double(stats.goldEarned) / minutes), label: "Gold/min", weight: .bold, spacing: 1)
                MiniStat(value: String(format: "%.0f", Double(stats.damageDealtToChampions) / minutes), label: "Damage/min", weight: .bold, spacing: 1)
                MiniStat(value: String(format: "%.1f", Double(stats.creepScore) / minutes), label: "Minions/min", weight: .bold, spacing: 1)
                MiniStat(value: "\(stats.soloKills)", label: "1v1 kills", weight: .bold, spacing: 1)
                MiniStat(value: "\(stats.largestKillingSpree)", label: "Kill streak", weight: .bold, spacing: 1)
            }
            // Five across, wrapping to a grid only when they no longer fit.
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: rateStatMinWidth), spacing: 14)], spacing: 10) { rates }
            } else {
                HStack(spacing: 14) { rates }
            }

            if stats.firstBloodKill || stats.objectivesStolen > 0 {
                HStack(spacing: 8) {
                    if stats.firstBloodKill {
                        highlightChip(text: "First Blood", icon: "drop.fill", tint: .red)
                    }
                    if stats.objectivesStolen > 0 {
                        highlightChip(text: "Stolen ×\(stats.objectivesStolen)", icon: "hand.raised.fill", tint: .purple)
                    }
                }
            }

            let ownedItems = stats.items.filter { $0 != 0 }
            if !ownedItems.isEmpty {
                Divider()
                Text("Items").font(.caption).foregroundStyle(.secondary)
                // Wraps once the scaled icons are wider than the card.
                let icons = ForEach(ownedItems, id: \.self) { item in
                    ItemIconView(itemID: item, size: detailItemSize)
                }
                let layout = dynamicTypeSize.isAccessibilitySize
                    ? AnyLayout(FlowLayout(spacing: 6))
                    : AnyLayout(HStackLayout(spacing: 6))
                layout { icons }
            }
        }
    }

    private func highlightChip(text: String, icon: String, tint: Color) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).scaledFont(10)
            Text(text).font(.caption.weight(.semibold))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(tint.opacity(0.12), in: Capsule())
    }

    private func tftStatsSection(_ stats: TFTStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Performance").font(.headline)
            SectionCard {
                LabeledContent("Placement", value: "#\(stats.placement)")
                Divider()
                LabeledContent("Level", value: "\(stats.level)")
                if !stats.traits.isEmpty {
                    Divider()
                    LabeledContent("Traits", value: stats.traits.joined(separator: ", "))
                }
                if !stats.units.isEmpty {
                    Divider()
                    LabeledContent("Units", value: stats.units.joined(separator: ", "))
                }
            }
        }
    }

    private var tabPicker: some View {
        Picker("View", selection: $selectedTab) {
            ForEach(DetailTab.allCases) { tab in
                Text(tab == .you && !match.isOwnHistory ? "Player" : tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .players:
            scoreboardSection
        case .team:
            TeamComparisonView(match: match)
        case .matchup:
            PlayerMatchupView(match: match)
        case .you:
            if let stats = match.leagueStats { leagueStatsSection(stats) }
        }
    }

    /// Your team first, each in lane order, one row per player.
    private var scoreboardSection: some View {
        let awards = PerformanceScore.awards(in: match)
        let linkedTeamId = match.focusParticipant?.teamId
        let teamIds = Set(match.participants.map(\.teamId)).sorted { a, b in
            a == linkedTeamId || (b != linkedTeamId && a < b)
        }
        let laneOrder = ["Top", "Jungle", "Mid", "ADC", "Support"]

        return VStack(alignment: .leading, spacing: 12) {
            // Once, above both teams, rather than a label on every row.
            Label("Each row: rating out of 10 · kills / deaths / assists · items. Tap a player for more.", systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(teamIds, id: \.self) { teamId in
                let players = match.participants
                    .filter { $0.teamId == teamId }
                    .sorted { (laneOrder.firstIndex(of: $0.role) ?? 5) < (laneOrder.firstIndex(of: $1.role) ?? 5) }
                VStack(alignment: .leading, spacing: 0) {
                    teamHeader(players, isFocusTeam: teamId == linkedTeamId)
                    ForEach(Array(players.enumerated()), id: \.element.id) { index, player in
                        if index > 0 { Divider() }
                        ScoreboardRowView(
                            participant: player,
                            match: match,
                            award: MatchAward(puuid: player.puuid, awards: awards),
                            region: region,
                            platform: platform
                        )
                    }
                }
                .cardSurface()
            }
        }
    }

    /// Team totals on the team's own header: a personal 6/12/5 reads very
    /// differently when the team went 36/34/32 than when it went 12/40/10.
    private func teamHeader(_ players: [MatchParticipantSummary], isFocusTeam: Bool) -> some View {
        let won = players.first?.win ?? false
        let kills = players.map(\.kills).reduce(0, +)
        let deaths = players.map(\.deaths).reduce(0, +)
        let assists = players.map(\.assists).reduce(0, +)
        let gold = Double(players.map(\.goldEarned).reduce(0, +)) / 1000

        return HStack(spacing: 6) {
            Capsule()
                // Your side is blue in your own games; a browsed game keeps
                // Riot's real sides so "Red team" is never drawn blue.
                .fill((match.isOwnHistory ? isFocusTeam : players.first?.teamId == 100) ? Theme.ally : Theme.enemy)
                .frame(width: 3, height: 14)
            Text(teamTitle(isFocusTeam: isFocusTeam, teamId: players.first?.teamId))
                .font(.subheadline.weight(.semibold))
            Text(won ? "Victory" : "Defeat")
                .font(.caption.weight(.semibold))
                .foregroundStyle(won ? Theme.win : Theme.loss)
            Spacer(minLength: 6)
            Text("K/D/A \(Text("\(kills)/\(deaths)/\(assists)").fontWeight(.semibold))")
                .font(.caption.monospacedDigit())
            Text("Gold \(String(format: "%.1fk", gold))")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.8)
        .padding(.bottom, 6)
        .accessibilityElement(children: .combine)
    }

    /// "Your team" only in your own games; a browsed game isn't yours.
    private func teamTitle(isFocusTeam: Bool, teamId: Int?) -> String {
        if match.isOwnHistory { return isFocusTeam ? "Your team" : "Enemy team" }
        return teamId == 100 ? "Blue team" : "Red team"
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reflection").font(.headline)
            SectionCard {
                Text("What happened")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextEditor(text: $match.notes)
                    .frame(minHeight: notesMinHeight)
                    .scrollContentBackground(.hidden)

                Divider()

                Text("Tags")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                // Tags are what make the journal queryable later — the notes
                // say what happened, the tags are what Stats can group by.
                TagEditor(tags: $match.tags, vocabulary: ReflectionTag.vocabulary(for: match.game, usedIn: allMatches))
            }
        }
    }

    private func participationRing(_ percent: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(Theme.accent, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(percent)%")
                    .scaledFont(15, relativeTo: .subheadline, weight: .bold, monospacedDigit: true)
                Text("kill share")
                    .scaledFont(8)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: participationRingSize, height: participationRingSize)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kill participation \(percent) percent")
    }

    private func iconStat(_ label: String, _ value: String, icon: String, tint: Color) -> some View {
        VStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundStyle(tint)
                .frame(width: statGlyphSize, height: statGlyphSize)
                .background(tint.opacity(0.15), in: Circle())
            Text(value)
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            Text(label)
                .scaledFont(9)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 8)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    private var durationString: String {
        let minutes = match.gameDurationSeconds / 60
        let seconds = match.gameDurationSeconds % 60
        return String(format: "%d:%02d", minutes, seconds)
    }
}

/// Wraps a match for the coach screen so that push lives in the navigation
/// path like every other one.
///
/// A view-based `NavigationLink { CoachChatView(...) }` pushes a screen the
/// path knows nothing about, so programmatic navigation — a tapped reflection
/// reminder resetting the stack to one match — could not clear it, and the
/// player landed back on whatever the coach was last discussing.
struct CoachRoute: Hashable {
    let match: Match
}
