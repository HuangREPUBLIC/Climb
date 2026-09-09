import SwiftUI
import SwiftData

struct MatchDetailView: View {
    @Bindable var match: Match
    @Query private var accounts: [LinkedAccount]
    /// Only for the tag vocabulary — a tag invented on one match should be
    /// offered as a chip on the next one instead of retyped.
    @Query private var allMatches: [Match]

    private enum DetailTab: String, CaseIterable, Identifiable {
        case match = "Match"
        case team = "Team"
        case matchup = "Matchup"
        var id: String { rawValue }
    }

    @State private var selectedTab: DetailTab = .match

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
    @ScaledMetric(relativeTo: .title3) private var bannerSlant: CGFloat = 16

    private var statTileColumns: [GridItem] {
        dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.adaptive(minimum: statTileMinWidth), spacing: 10)]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
    }

    private var region: RiotRegion? {
        RiotRegion(rawValue: accounts.first?.region ?? "")
    }

    private var platform: RiotPlatform? {
        RiotPlatform(rawValue: accounts.first?.platform ?? "")
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 0) {
                header

                VStack(alignment: .leading, spacing: 16) {
                    if let stats = match.leagueStats {
                        leagueStatsSection(stats)
                    }

                    if let stats = match.tftStats {
                        tftStatsSection(stats)
                    }

                    if !match.participants.isEmpty {
                        tabPicker
                        tabContent
                    }

                    reflectionSection

                    NavigationLink(value: CoachRoute(match: match)) {
                        Label("Ask the AI Coach", systemImage: "bubble.left.and.bubble.right")
                            .frame(maxWidth: .infinity)
                            .padding()
                            .background(Color.accentColor.opacity(0.15))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                }
                .padding()
            }
            .readableContentWidth()
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle(match.leagueStats?.champion ?? (match.tftStats != nil ? "Teamfight Tactics" : match.game.shortName))
        .navigationBarTitleDisplayMode(.inline)
        .navigationDestination(for: CoachRoute.self) { route in
            CoachChatView(match: route.match)
        }
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
                        AsyncImage(url: url) { phase in
                            if let image = phase.image {
                                image.resizable().aspectRatio(contentMode: .fill)
                            } else {
                                Rectangle().fill(.secondary.opacity(0.2))
                            }
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
                    .foregroundStyle(stats.placement <= 4 ? .green : .red)
                Text("Teamfight Tactics")
                    .font(.headline)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 32)
            .background(Color(.secondarySystemGroupedBackground))
        }
    }

    /// Outcome headline with the score beside it, then queue and timing
    /// underneath — the reference app's hero layout. The score sits in a
    /// filled chip because bare tinted text over splash art fails contrast at
    /// low scores (grey on dark = invisible).
    @ViewBuilder
    private func headerContent(_ stats: LeagueStats) -> some View {
        let headline = Text(match.win ? "VICTORY" : "DEFEAT")
            .scaledFont(32, relativeTo: .largeTitle, weight: .heavy, design: .rounded)
            .foregroundStyle(match.win ? Color.green : Color.red)
            .shadow(color: .black.opacity(0.6), radius: 6, y: 2)

        let badge = Group {
            if let multiKill = stats.multiKillLabel {
                Text(multiKill)
                    .font(.caption.bold())
                    .padding(.horizontal, 8)
                    .padding(.vertical, 3)
                    .background(.yellow.opacity(0.9))
                    .foregroundStyle(.black)
                    .clipShape(Capsule())
            }
        }

        let outcome = VStack(alignment: .leading, spacing: 10) {
            // Baseline-aligned beside the headline, and only wrapping onto a
            // second line once "VICTORY" alone fills the width.
            if dynamicTypeSize.isAccessibilitySize {
                FlowLayout(spacing: 12) { headline; badge }
            } else {
                HStack(alignment: .firstTextBaseline, spacing: 12) { headline; badge }
            }

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
                .scaledFont(30, relativeTo: .largeTitle, weight: .heavy, design: .rounded, monospacedDigit: true)
                .foregroundStyle(.white)
            Text("EST. SCORE")
                .scaledFont(8, weight: .bold)
                .tracking(0.5)
                .foregroundStyle(.white.opacity(0.8))
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 9)
        .background(PerformanceScore.chipColor(for: score))
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous)
                .strokeBorder(.white.opacity(0.25), lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.35), radius: 8, y: 3)
    }

    /// Outcome already reads loud and clear on the splash header, so this is
    /// a light metadata strip rather than another stacked card repeating it.
    private var resultSection: some View {
        HStack(spacing: 8) {
            metaChip(icon: "flag.checkered", text: match.queueType)
            metaChip(icon: "clock", text: durationString)
            metaChip(icon: "calendar", text: match.timestamp.formatted(date: .abbreviated, time: .omitted))
            Spacer(minLength: 0)
        }
    }

    private func metaChip(icon: String, text: String) -> some View {
        HStack(spacing: 4) {
            Image(systemName: icon).scaledFont(10)
            Text(text).font(.caption)
        }
        .foregroundStyle(.secondary)
        .padding(.horizontal, 9)
        .padding(.vertical, 5)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(Capsule())
    }

    private func leagueStatsSection(_ stats: LeagueStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Performance").font(.headline)
            sectionCard {
                // KDA headline with the kill/death/assist split colour-coded
                // and kill participation shown as a ring, rather than three
                // more identical grey rows.
                HStack(alignment: .center, spacing: 16) {
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 3) {
                            Text("\(stats.kills)").foregroundStyle(.primary)
                            Text("/").foregroundStyle(.tertiary)
                            Text("\(stats.deaths)").foregroundStyle(.red)
                            Text("/").foregroundStyle(.tertiary)
                            Text("\(stats.assists)").foregroundStyle(.primary)
                        }
                        .font(.title2.bold().monospacedDigit())

                        Text("\(String(format: "%.2f", stats.kda)) KDA · \(stats.role)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }

                    Spacer()

                    if let kp = killParticipation(for: stats) {
                        participationRing(kp)
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
                    iconStat("CS", "\(stats.creepScore)", icon: "leaf.fill", tint: .green)
                    iconStat("Gold", stats.goldEarned.formatted(), icon: "dollarsign.circle.fill", tint: .yellow)
                    iconStat("Vision", "\(stats.visionScore)", icon: "eye.fill", tint: .cyan)
                    iconStat("Dealt", stats.damageDealtToChampions.formatted(), icon: "burst.fill", tint: .red)
                    iconStat("Taken", stats.damageTaken.formatted(), icon: "shield.fill", tint: .blue)
                    iconStat("Healed", stats.match?.participants.first(where: \.isLinkedPlayer)?.totalHeal.formatted() ?? "0", icon: "cross.case.fill", tint: .pink)
                }

                // Per-minute rates and standout moments, folded in here rather
                // than repeated in a separate card.
                let minutes = max(Double(match.gameDurationSeconds) / 60, 1)
                let rates = Group {
                    rateStat("Gold/min", String(format: "%.0f", Double(stats.goldEarned) / minutes))
                    rateStat("Dmg/min", String(format: "%.0f", Double(stats.damageDealtToChampions) / minutes))
                    rateStat("CS/min", String(format: "%.1f", Double(stats.creepScore) / minutes))
                    rateStat("Solo", "\(stats.soloKills)")
                    rateStat("Spree", "\(stats.largestKillingSpree)")
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
                    if dynamicTypeSize.isAccessibilitySize {
                        FlowLayout(spacing: 6) { icons }
                    } else {
                        HStack(spacing: 6) { icons }
                    }
                }
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
        .background(tint.opacity(0.12))
        .clipShape(Capsule())
    }

    private func tftStatsSection(_ stats: TFTStats) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Performance").font(.headline)
            sectionCard {
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
                Text(tab.rawValue).tag(tab)
            }
        }
        .pickerStyle(.segmented)
    }

    @ViewBuilder
    private var tabContent: some View {
        switch selectedTab {
        case .match:
            scoreboardSection
        case .team:
            TeamComparisonView(match: match)
        case .matchup:
            PlayerMatchupView(match: match, region: region)
        }
    }

    private var scoreboardSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Scoreboard").font(.headline)
            teamTotalsBanner
            // The scoreboard is the densest thing in the app — ten players,
            // each with a portrait, a loadout and a stat line.
            sectionCard {
                if let matchups = laneMatchups {
                    let awards = PerformanceScore.awards(in: match)
                    ForEach(Array(matchups.enumerated()), id: \.offset) { index, matchup in
                        LaneMatchupRowView(
                            role: matchup.role,
                            left: matchup.left,
                            right: matchup.right,
                            region: region,
                            platform: platform,
                            match: match,
                            mvpPUUID: awards.mvp,
                            svpPUUID: awards.svp
                        )
                        if index < matchups.count - 1 {
                            Divider()
                        }
                    }
                } else {
                    let blue = match.participants.filter { $0.teamId == 100 }
                    let red = match.participants.filter { $0.teamId == 200 }
                    if !blue.isEmpty {
                        Text("Blue Team").font(.caption.weight(.semibold)).foregroundStyle(.blue)
                        ForEach(blue) { participant in
                            participantRow(participant)
                        }
                    }
                    if !red.isEmpty {
                        if !blue.isEmpty { Divider().padding(.vertical, 2) }
                        Text("Red Team").font(.caption.weight(.semibold)).foregroundStyle(.red)
                        ForEach(red) { participant in
                            participantRow(participant)
                        }
                    }
                }
            }
            .denseRowScaling()
        }
    }

    /// Both teams' aggregate kills/deaths/assists, above the ten rows.
    ///
    /// A personal 6/12/5 reads completely differently depending on whether the
    /// team as a whole was 36/34/32 or 12/40/10, and nothing else on this
    /// screen says which. The two sides meet at an angle rather than a vertical
    /// seam so the band reads as one comparison instead of two panels.
    @ViewBuilder
    private var teamTotalsBanner: some View {
        let linkedTeamId = match.participants.first(where: \.isLinkedPlayer)?.teamId ?? 100
        let ally = match.participants.filter { $0.teamId == linkedTeamId }
        let enemy = match.participants.filter { $0.teamId != linkedTeamId }

        if !ally.isEmpty, !enemy.isEmpty {
            let allySide = teamTotalsSide(
                label: "Your team",
                outcome: match.win ? "Victory" : "Defeat",
                totals: teamKDA(ally),
                won: match.win,
                alignment: .leading
            )
            let enemySide = teamTotalsSide(
                label: "Enemy",
                outcome: match.win ? "Defeat" : "Victory",
                totals: teamKDA(enemy),
                won: !match.win,
                alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .trailing
            )

            Group {
                // The angled split only works while the two sides share a row.
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 10) {
                        allySide
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Theme.ally.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                        enemySide
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(12)
                            .background(Theme.enemy.opacity(0.14))
                            .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                    }
                } else {
                    HStack(spacing: 0) {
                        allySide
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.vertical, 10)
                            .padding(.leading, 14)
                            .padding(.trailing, bannerSlant + 8)
                            .background(Theme.ally.opacity(0.14), in: SlantedBlock(slantsTrailing: true, slant: bannerSlant))

                        Text("VS")
                            .font(.caption2.weight(.black))
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)

                        enemySide
                            .frame(maxWidth: .infinity, alignment: .trailing)
                            .padding(.vertical, 10)
                            .padding(.trailing, 14)
                            .padding(.leading, bannerSlant + 8)
                            .background(Theme.enemy.opacity(0.14), in: SlantedBlock(slantsTrailing: false, slant: bannerSlant))
                    }
                    .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
            }
            .accessibilityElement(children: .combine)
        }
    }

    private func teamTotalsSide(
        label: String,
        outcome: String,
        totals: String,
        won: Bool,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 1) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            // Tabular digits: the two sides' totals sit either side of the VS
            // and would jitter against each other otherwise.
            Text(totals)
                .font(.title3.weight(.bold).monospacedDigit())
            Text(outcome)
                .font(.caption.weight(.semibold))
                .foregroundStyle(won ? Theme.win : Theme.loss)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
    }

    private func teamKDA(_ players: [MatchParticipantSummary]) -> String {
        let kills = players.map(\.kills).reduce(0, +)
        let deaths = players.map(\.deaths).reduce(0, +)
        let assists = players.map(\.assists).reduce(0, +)
        return "\(kills)/\(deaths)/\(assists)"
    }

    /// Pairs each role (Top/Jungle/Mid/ADC/Support) against its lane
    /// opponent, linked player's team first. Falls back to a plain two-team
    /// list (nil here) for ARAM/arena modes where roles aren't meaningful.
    private var laneMatchups: [(role: String, left: MatchParticipantSummary?, right: MatchParticipantSummary?)]? {
        let roleOrder = ["Top", "Jungle", "Mid", "ADC", "Support"]
        let byRole = Dictionary(grouping: match.participants) { $0.role }
        guard match.participants.allSatisfy({ roleOrder.contains($0.role) }) else { return nil }

        let linkedTeamId = match.participants.first(where: \.isLinkedPlayer)?.teamId ?? 100
        return roleOrder.compactMap { role -> (String, MatchParticipantSummary?, MatchParticipantSummary?)? in
            guard let players = byRole[role], !players.isEmpty else { return nil }
            let left = players.first { $0.teamId == linkedTeamId }
            let right = players.first { $0.teamId != linkedTeamId }
            return (role, left, right)
        }
    }

    @ViewBuilder
    private func participantRow(_ participant: MatchParticipantSummary) -> some View {
        if participant.isLinkedPlayer {
            ParticipantRowView(participant: participant)
        } else if let region {
            NavigationLink {
                PlayerProfileView(
                    puuid: participant.puuid,
                    riotIdGameName: participant.riotIdGameName,
                    riotIdTagline: participant.riotIdTagline,
                    region: region,
                    platform: platform
                )
            } label: {
                ParticipantRowView(participant: participant)
            }
            .buttonStyle(PressableButtonStyle())
        } else {
            ParticipantRowView(participant: participant)
        }
    }

    private var reflectionSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Reflection").font(.headline)
            sectionCard {
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
                TagEditor(tags: $match.tags, vocabulary: tagVocabulary)
            }
        }
    }

    private var tagVocabulary: [String] {
        ReflectionTag.vocabulary(for: match.game, usedIn: allMatches)
    }

    private func killParticipation(for stats: LeagueStats) -> Int? {
        guard let linkedTeamId = match.participants.first(where: \.isLinkedPlayer)?.teamId else { return nil }
        let teamKills = match.participants.filter { $0.teamId == linkedTeamId }.map(\.kills).reduce(0, +)
        guard teamKills > 0 else { return nil }
        return Int((Double(stats.kills + stats.assists) / Double(teamKills) * 100).rounded())
    }

    private func participationRing(_ percent: Int) -> some View {
        ZStack {
            Circle()
                .stroke(Color.secondary.opacity(0.15), lineWidth: 6)
            Circle()
                .trim(from: 0, to: CGFloat(percent) / 100)
                .stroke(Color.accentColor, style: StrokeStyle(lineWidth: 6, lineCap: .round))
                .rotationEffect(.degrees(-90))
            VStack(spacing: -1) {
                Text("\(percent)%")
                    .scaledFont(15, relativeTo: .subheadline, weight: .bold, design: .rounded, monospacedDigit: true)
                Text("KP")
                    .scaledFont(8)
                    .foregroundStyle(.secondary)
            }
        }
        .frame(width: participationRingSize, height: participationRingSize)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("Kill participation \(percent) percent")
    }

    private func rateStat(_ label: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .scaledFont(9)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
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
        .background(Color(.tertiarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    private func statTile(_ label: String, _ value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label).font(.caption2).foregroundStyle(.secondary)
            Text(value).font(.subheadline.weight(.semibold)).monospacedDigit()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: Theme.itemSpacing) {
            content()
        }
        .cardSurface()
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

/// A block with one slanted inner edge, so the two team totals meet at an angle
/// instead of a hard vertical seam.
private struct SlantedBlock: Shape {
    let slantsTrailing: Bool
    var slant: CGFloat = 16

    func path(in rect: CGRect) -> Path {
        var path = Path()
        if slantsTrailing {
            path.move(to: CGPoint(x: rect.minX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX - slant, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        } else {
            path.move(to: CGPoint(x: rect.minX + slant, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        }
        path.closeSubpath()
        return path
    }
}
