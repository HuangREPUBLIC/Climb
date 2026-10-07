import SwiftUI
import Charts

/// The "Team" tab (团队) of the match detail screen: objective totals,
/// aggregate stat comparison bars, and a sortable player ranking list —
/// modeled on the reference companion app's team breakdown screen.
struct TeamComparisonView: View {
    let match: Match

    private enum RankMetric: String, CaseIterable, Identifiable {
        case damage = "Damage"
        case tanking = "Tanking"
        case gold = "Gold"
        var id: String { rawValue }

        var label: String {
            switch self {
            case .damage: return "Damage"
            case .tanking: return "Tanking"
            case .gold: return "Gold"
            }
        }
    }

    @State private var rankMetric: RankMetric = .damage

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .caption) private var objectiveIconSize: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var objectiveTileMinWidth: CGFloat = 72
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 150
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 8
    @ScaledMetric(relativeTo: .caption) private var rowPortraitSize: CGFloat = 30
    @ScaledMetric(relativeTo: .caption2) private var medalWidth: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var ribbonWidth: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var ribbonHeight: CGFloat = 18

    private var linkedTeamId: Int {
        match.focusParticipant?.teamId ?? 100
    }
    private var allyTeam: [MatchParticipantSummary] { match.participants.filter { $0.teamId == linkedTeamId } }
    private var enemyTeam: [MatchParticipantSummary] { match.participants.filter { $0.teamId != linkedTeamId } }
    private var allyObjectives: TeamStats? { match.teamStats.first { $0.teamId == linkedTeamId } }
    private var enemyObjectives: TeamStats? { match.teamStats.first { $0.teamId != linkedTeamId } }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            overviewCard
            if !match.goldTimeline.isEmpty {
                goldDifferenceCard
            }
            rankingSection
        }
    }

    /// Gold lead over time — the shape of the game, not just its final score.
    /// Built from timeline participant frames captured at import.
    private var goldDifferenceCard: some View {
        let last = match.goldTimeline.max { $0.minute < $1.minute }

        return sectionCard {
            HStack {
                Text("Gold difference").font(.headline)
                Spacer()
                if let last {
                    Text(last.goldDifference >= 0 ? "+\(last.goldDifference)" : "\(last.goldDifference)")
                        .font(.subheadline.weight(.bold).monospacedDigit())
                        .foregroundStyle(last.goldDifference >= 0 ? Theme.good : Theme.poor)
                }
            }

            GoldLeadChart(points: match.goldTimeline)
                .frame(height: chartHeight)

            Text("Above the line = your team ahead")
                .scaledFont(9)
                .foregroundStyle(.tertiary)
        }
    }

    /// Objectives and team totals live in one card — they're the same story
    /// (how the two teams compared), so splitting them into separate floating
    /// panels just added visual noise.
    private var overviewCard: some View {
        sectionCard {
            if allyObjectives != nil || enemyObjectives != nil {
                objectivesGrid
                Divider().padding(.vertical, 4)
            }
            statBars
        }
    }

    // MARK: - Objectives

    private var objectivesGrid: some View {
        let ally = allyObjectives
        let enemy = enemyObjectives
        // Four fixed columns at normal text sizes — that is the layout. Only
        // once the text is too large for four does the grid go adaptive and
        // reflow to fewer.
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.adaptive(minimum: objectiveTileMinWidth), spacing: 14)]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return Group {
            LazyVGrid(columns: columns, spacing: 14) {
                objectiveTile(url: ObjectiveIconService.baronURL, label: "Baron", ally: ally?.baronKills ?? 0, enemy: enemy?.baronKills ?? 0)
                objectiveTile(url: ObjectiveIconService.url(named: "dragon"), label: "Dragon", ally: ally?.dragonKills ?? 0, enemy: enemy?.dragonKills ?? 0)
                objectiveTile(url: ObjectiveIconService.heraldURL, label: "Herald", ally: ally?.heraldKills ?? 0, enemy: enemy?.heraldKills ?? 0)
                // Voidgrubs only exist on matches played since 2024; the tile
                // is hidden rather than showing a permanent 0/0 on older games.
                if (ally?.voidgrubKills ?? 0) + (enemy?.voidgrubKills ?? 0) > 0 {
                    objectiveTile(url: ObjectiveIconService.voidgrubURL, label: "Voidgrubs", ally: ally?.voidgrubKills ?? 0, enemy: enemy?.voidgrubKills ?? 0)
                }
                objectiveTile(url: ObjectiveIconService.turretURL, label: "Towers", ally: ally?.towerKills ?? 0, enemy: enemy?.towerKills ?? 0)
                objectiveTile(url: ObjectiveIconService.inhibitorURL, label: "Inhibitors", ally: ally?.inhibitorKills ?? 0, enemy: enemy?.inhibitorKills ?? 0)
            }
        }
    }

    private func objectiveTile(url: URL?, label: String, ally: Int, enemy: Int) -> some View {
        VStack(spacing: 6) {
            ObjectiveIconView(url: url, size: objectiveIconSize)
            HStack(spacing: 4) {
                Text("\(ally)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(.blue)
                Text("/").font(.caption).foregroundStyle(.secondary)
                Text("\(enemy)").font(.subheadline.bold().monospacedDigit()).foregroundStyle(.red)
            }
            Text(label).font(.caption2).foregroundStyle(.secondary).lineLimit(1).minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(label): your team \(ally), enemy team \(enemy)")
    }

    // MARK: - Aggregate stat bars

    private var statBars: some View {
        Group {
            teamComparisonBar(label: "Gold", left: allyTeam.map(\.goldEarned).reduce(0, +), right: enemyTeam.map(\.goldEarned).reduce(0, +))
            Divider()
            teamComparisonBar(label: "Damage to champions", left: allyTeam.map(\.damageDealtToChampions).reduce(0, +), right: enemyTeam.map(\.damageDealtToChampions).reduce(0, +))
            Divider()
            teamComparisonBar(label: "Damage taken", left: allyTeam.map(\.damageTaken).reduce(0, +), right: enemyTeam.map(\.damageTaken).reduce(0, +))
            Divider()
            teamComparisonBar(label: "Healing", left: allyTeam.map(\.totalHeal).reduce(0, +), right: enemyTeam.map(\.totalHeal).reduce(0, +))
        }
    }

    private func teamComparisonBar(label: String, left: Int, right: Int) -> some View {
        let total = max(left + right, 1)
        let leftFraction = CGFloat(left) / CGFloat(total)
        let leftPercent = Int((leftFraction * 100).rounded())
        let leftText = Text("\(leftPercent)% \(left)").font(.caption.monospacedDigit()).foregroundStyle(.blue)
        let rightText = Text("\(right) \(100 - leftPercent)%").font(.caption.monospacedDigit()).foregroundStyle(.red)
        let title = Text(label).font(.caption).foregroundStyle(.secondary)

        return VStack(spacing: 4) {
            // The label moves onto its own line rather than squeezing the two
            // totals off the edges once the text no longer fits one row.
            ViewThatFits(in: .horizontal) {
                HStack {
                    leftText
                    Spacer(minLength: 6)
                    title.lineLimit(1)
                    Spacer(minLength: 6)
                    rightText
                }
                VStack(spacing: 2) {
                    title.frame(maxWidth: .infinity, alignment: .leading)
                    HStack { leftText; Spacer(minLength: 6); rightText }
                }
            }
            GeometryReader { geo in
                HStack(spacing: 2) {
                    LinearGradient(colors: [.blue.opacity(0.7), .blue], startPoint: .leading, endPoint: .trailing)
                        .frame(width: max(geo.size.width * leftFraction - 1, 0))
                    LinearGradient(colors: [.red, .red.opacity(0.7)], startPoint: .leading, endPoint: .trailing)
                }
            }
            .frame(height: barHeight)
            .clipShape(Capsule())
        }
    }

    // MARK: - Player ranking

    private var rankingSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Picker("Rank by", selection: $rankMetric) {
                ForEach(RankMetric.allCases) { metric in
                    Text(metric.label).tag(metric)
                }
            }
            .pickerStyle(.segmented)

            sectionCard {
                let ranked = rankedParticipants
                let total = max(ranked.map(metricValue).reduce(0, +), 1)

                // Podium for the top three, table for the rest — the reference
                // app's layout, and it makes the standouts readable at a glance
                // instead of burying them in a uniform list.
                // Three podium cards side by side stop being readable at
                // accessibility sizes; there they become three ranked rows
                // like the rest of the table.
                if ranked.count >= 3, !dynamicTypeSize.isAccessibilitySize {
                    HStack(alignment: .top, spacing: 8) {
                        podiumEntry(ranked[1], rank: 2, total: total)
                        podiumEntry(ranked[0], rank: 1, total: total)
                        podiumEntry(ranked[2], rank: 3, total: total)
                    }
                    .padding(.bottom, 4)
                    Divider()
                }

                let firstTableRow = dynamicTypeSize.isAccessibilitySize || ranked.count < 3 ? 0 : 3
                ForEach(Array(ranked.enumerated()), id: \.element.puuid) { index, participant in
                    if index >= firstTableRow {
                        playerRankRow(rank: index + 1, participant: participant, total: total)
                            .denseRowScaling()
                        if index < ranked.count - 1 { Divider() }
                    }
                }
            }
        }
    }

    private var rankedParticipants: [MatchParticipantSummary] {
        match.participants.sorted { metricValue($0) > metricValue($1) }
    }

    private func metricValue(_ participant: MatchParticipantSummary) -> Int {
        switch rankMetric {
        case .damage: return participant.damageDealtToChampions
        case .tanking: return participant.damageTaken
        case .gold: return participant.goldEarned
        }
    }

    /// Podium card: portrait ringed in the team colour, medal ribbon with the
    /// placing, then value and share.
    private func podiumEntry(_ participant: MatchParticipantSummary, rank: Int, total: Int) -> some View {
        let value = metricValue(participant)
        let percent = Int((Double(value) / Double(total) * 100).rounded())
        let isAlly = participant.teamId == linkedTeamId
        let ringColor: Color = isAlly ? .blue : .red
        let portraitSize: CGFloat = rank == 1 ? 62 : 52

        return VStack(spacing: 5) {
            ZStack(alignment: .bottom) {
                ChampionIconView(championName: participant.champion, size: portraitSize)
                    .clipShape(Circle())
                    .overlay(Circle().strokeBorder(ringColor, lineWidth: 2.5))

                medalRibbon(rank)
                    .offset(y: 9)
            }
            .padding(.bottom, 9)

            Text(participant.isLinkedPlayer ? "\(participant.riotIdGameName) (You)" : participant.riotIdGameName)
                .scaledFont(10, weight: participant.isLinkedPlayer ? .bold : .medium)
                .lineLimit(1)
                .minimumScaleFactor(0.8)

            Text(value.formatted())
                .font(.caption.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text("\(percent)%")
                .scaledFont(9)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, rank == 1 ? 0 : 8)
        .accessibilityElement(children: .combine)
    }

    private func medalRibbon(_ rank: Int) -> some View {
        let colors: [Color] = [.yellow, Color(white: 0.72), .brown]
        let tint = colors[min(max(rank - 1, 0), 2)]
        return Text("\(rank)")
            .scaledFont(10, weight: .black)
            .foregroundStyle(.white)
            .frame(width: ribbonWidth, height: ribbonHeight)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous).strokeBorder(.white.opacity(0.6), lineWidth: 1)
            )
    }

    private func playerRankRow(rank: Int, participant: MatchParticipantSummary, total: Int) -> some View {
        let value = metricValue(participant)
        let percent = Int((Double(value) / Double(total) * 100).rounded())
        return HStack(spacing: 10) {
            medal(for: rank)
                .frame(width: medalWidth)
            ChampionIconView(championName: participant.champion, size: rowPortraitSize)
            VStack(alignment: .leading, spacing: 1) {
                Text(participant.isLinkedPlayer ? "\(participant.riotIdGameName) (You)" : participant.riotIdGameName)
                    .font(.caption.weight(participant.isLinkedPlayer ? .bold : .regular))
                    .lineLimit(1)
                Text(participant.teamId == linkedTeamId ? "Ally" : "Enemy")
                    .font(.caption2)
                    .foregroundStyle(participant.teamId == linkedTeamId ? .blue : .red)
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 1) {
                Text("\(value)").font(.subheadline.weight(.semibold).monospacedDigit())
                Text("\(percent)%").font(.caption2).foregroundStyle(.secondary)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func medal(for rank: Int) -> some View {
        switch rank {
        case 1:
            Image(systemName: "1.circle.fill").foregroundStyle(.yellow)
        case 2:
            Image(systemName: "2.circle.fill").foregroundStyle(.gray)
        case 3:
            Image(systemName: "3.circle.fill").foregroundStyle(.brown)
        default:
            Text("\(rank)").font(.caption).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private func sectionCard<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            content()
        }
        .cardSurface()
    }
}

/// Your team's gold lead by minute: above the line ahead, below behind.
/// Shared by the Team tab and the AI review.
struct GoldLeadChart: View {
    let points: [GoldTimelinePoint]

    var body: some View {
        let points = points.sorted { $0.minute < $1.minute }
        let peak = max(points.map { abs($0.goldDifference) }.max() ?? 1000, 1000)
        Chart {
            ForEach(points) { point in
                // Split at zero so a lead fills green and a deficit red.
                AreaMark(
                    x: .value("Minute", point.minute),
                    y: .value("Gold", max(point.goldDifference, 0)),
                    series: .value("Side", "ahead"),
                    stacking: .unstacked
                )
                .foregroundStyle(Theme.good.opacity(0.25))
                AreaMark(
                    x: .value("Minute", point.minute),
                    y: .value("Gold", min(point.goldDifference, 0)),
                    series: .value("Side", "behind"),
                    stacking: .unstacked
                )
                .foregroundStyle(Theme.poor.opacity(0.25))
                LineMark(
                    x: .value("Minute", point.minute),
                    y: .value("Gold", point.goldDifference),
                    series: .value("Side", "lead")
                )
                .foregroundStyle(Theme.accent)
                .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
            }
            RuleMark(y: .value("Even", 0))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: -peak...peak)
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 5)) { value in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel {
                    if let minute = value.as(Int.self) {
                        Text("\(minute)m").scaledFont(9)
                    }
                }
            }
        }
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 3)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
    }
}
