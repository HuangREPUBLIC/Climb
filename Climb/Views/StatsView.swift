import SwiftUI
import SwiftData
import Charts

private struct ChampionRecord: Identifiable {
    let champion: String
    let games: Int
    let wins: Int
    let kda: Double
    var id: String { champion }
    var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) * 100 }
}

private struct KDAGamePoint: Identifiable {
    let index: Int
    let kda: Double
    let win: Bool
    var id: Int { index }
}

private struct RoleWinRate: Identifiable {
    let role: String
    let games: Int
    let winRate: Double
    var id: String { role }
}

private struct PlacementPoint: Identifiable {
    let date: Date
    let placement: Int
    var id: Date { date }
}

private struct TagWinRate: Identifiable {
    let tag: String
    let games: Int
    let wins: Int
    var id: String { tag }
    var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) * 100 }
}

/// Trend dashboards.
///
/// Cards on the grouped background rather than a plain `List`: this screen is
/// the app's analytical centrepiece, and grouped-list chrome made it read as a
/// settings page with charts embedded in it. The aggregation and the charts are
/// unchanged — only what surrounds them.
struct StatsView: View {
    @Query(sort: \Match.timestamp, order: .forward) private var allMatches: [Match]
    /// Shared with the Matches tab, so both screens stay on the same game.
    @AppStorage("selectedGame") private var selectedGame: Game = .league
    @State private var queueFilter: String?

    private var gameMatches: [Match] { allMatches.filter { $0.game == selectedGame && $0.isOwnHistory } }
    /// ARAM and normals would otherwise blend into a ranked win rate.
    private var matches: [Match] { gameMatches.filter { match in queueFilter.map { match.queueType == $0 } ?? true } }
    private var queues: [String] {
        Dictionary(grouping: gameMatches, by: \.queueType)
            .sorted { $0.value.count > $1.value.count }
            .map(\.key)
    }

    /// Magnitude series use the app accent (not a screen-local teal) so Stats
    /// belongs to the same product as everything else. Win rate stays
    /// green/red because that's a threshold read, not a magnitude.
    private let chartAccent = Theme.chart

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .subheadline) private var winRateColumnWidth: CGFloat = 46
    @ScaledMetric(relativeTo: .caption) private var countColumnWidth: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var listPortraitSize: CGFloat = 32
    @ScaledMetric(relativeTo: .caption2) private var legendDotSize: CGFloat = 6
    @ScaledMetric(relativeTo: .caption2) private var formPipHeight: CGFloat = 22
    /// Charts grow with the text so their axis labels stay proportionate
    /// rather than crowding a fixed-height plot.
    @ScaledMetric(relativeTo: .caption) private var chartHeight: CGFloat = 150
    @ScaledMetric(relativeTo: .caption) private var tallChartHeight: CGFloat = 160

    private var leagueMatches: [Match] { matches.filter { $0.leagueStats != nil } }
    private var tftMatches: [Match] { matches.filter { $0.tftStats != nil } }

    var body: some View {
        Group {
            if gameMatches.isEmpty {
                ContentUnavailableView(
                    "No stats yet",
                    systemImage: "chart.line.uptrend.xyaxis",
                    description: Text("Link a Riot account and sync some matches to see trends.")
                )
            } else {
                ScrollView {
                    if queues.count > 1 {
                        TagFilterBar(tags: queues, selection: $queueFilter)
                    }
                    VStack(alignment: .leading, spacing: Theme.sectionSpacing) {
                        if !leagueMatches.isEmpty {
                            headlineCard(for: leagueMatches)
                            section("KDA by game") { kdaChart }
                            section("Champions") { championTable }
                            section("Win rate by role") { roleChart }
                        }

                        if !tagStats.isEmpty {
                            section(
                                "Win rate by tag",
                                footnote: "From the tags you added yourself. This is the only breakdown here no stats site can give you — it checks the pattern you noticed against what actually happened."
                            ) {
                                tagList
                            }
                        }

                        if !tftMatches.isEmpty {
                            placementHeadlineCard
                            section("Placement trend") { placementChart }
                        }
                    }
                    .padding()
                    .readableContentWidth()
                }
                .background(Color(.systemGroupedBackground))
            }
        }
        .navigationTitle("Stats")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                GameFilterPicker(selection: $selectedGame, availableGames: Set(allMatches.map(\.game)))
            }
        }
        .onChange(of: selectedGame) { queueFilter = nil }
    }

    /// Title above, card below — the same rhythm as the match detail screen, so
    /// a heading always sits outside the surface it labels.
    @ViewBuilder
    private func section<Content: View>(
        _ title: String,
        footnote: String? = nil,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title).font(.headline)
            VStack(alignment: .leading, spacing: 10) {
                content()
            }
            .cardSurface()
            if let footnote {
                Text(footnote)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.horizontal, 4)
            }
        }
    }

    // MARK: - Headline

    /// Win rate, record, and the shape of the last ten games. The run of
    /// results is what a player actually wants first — a single averaged
    /// percentage hides whether they are climbing or sliding.
    private func headlineCard(for matches: [Match]) -> some View {
        let wins = matches.filter(\.win).count
        let winRate = matches.isEmpty ? 0 : Double(wins) / Double(matches.count) * 100
        let recent = Array(matches.suffix(10))

        return VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Win rate").font(.caption).foregroundStyle(.secondary)
                    Text("\(Int(winRate.rounded()))%")
                        .font(.largeTitle.bold().monospacedDigit())
                        .foregroundStyle(winRate >= 50 ? Theme.win : Theme.loss)
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Record").font(.caption).foregroundStyle(.secondary)
                    Text("\(wins)W – \(matches.count - wins)L")
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
            }

            if recent.count > 1 {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Last \(recent.count)")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                    HStack(spacing: 4) {
                        ForEach(Array(recent.enumerated()), id: \.offset) { _, match in
                            Capsule()
                                .fill(match.win ? Theme.win : Theme.loss)
                                .frame(height: formPipHeight)
                                .frame(maxWidth: .infinity)
                        }
                    }
                    .accessibilityElement(children: .ignore)
                    .accessibilityLabel("Last \(recent.count) games: \(recent.filter(\.win).count) wins")
                }
            }
        }
        .cardSurface()
    }

    private var placementHeadlineCard: some View {
        let placements = tftMatches.compactMap { $0.tftStats?.placement }
        let top4 = placements.filter { $0 <= 4 }.count
        let average = placements.isEmpty ? 0 : Double(placements.reduce(0, +)) / Double(placements.count)

        return VStack(alignment: .leading, spacing: 8) {
            Text("Teamfight Tactics").font(.headline)
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Top 4 rate").font(.caption).foregroundStyle(.secondary)
                    Text("\(placements.isEmpty ? 0 : Int((Double(top4) / Double(placements.count) * 100).rounded()))%")
                        .font(.largeTitle.bold().monospacedDigit())
                }
                Spacer(minLength: 12)
                VStack(alignment: .trailing, spacing: 2) {
                    Text("Average placement").font(.caption).foregroundStyle(.secondary)
                    Text(String(format: "%.1f", average))
                        .font(.title3.weight(.semibold).monospacedDigit())
                }
            }
            .cardSurface()
        }
    }

    // MARK: - Tags

    /// Groups the player's own tags against results. Needs at least two games
    /// on a tag: a 100% win rate off one game is noise, not a pattern.
    private var tagStats: [TagWinRate] {
        var counts: [String: (games: Int, wins: Int)] = [:]
        for match in matches {
            for tag in match.tags {
                var entry = counts[tag] ?? (games: 0, wins: 0)
                entry.games += 1
                if match.win { entry.wins += 1 }
                counts[tag] = entry
            }
        }
        return counts
            .filter { $0.value.games >= 2 }
            .map { TagWinRate(tag: $0.key, games: $0.value.games, wins: $0.value.wins) }
            .sorted { $0.games == $1.games ? $0.tag < $1.tag : $0.games > $1.games }
    }

    @ViewBuilder
    private var tagList: some View {
        ForEach(Array(tagStats.enumerated()), id: \.element.id) { index, entry in
            if index > 0 { Divider() }
            tagRow(entry)
        }
    }

    private func tagRow(_ entry: TagWinRate) -> some View {
        let record = Text("\(entry.wins)W-\(entry.games - entry.wins)L")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        let percentage = Text("\(Int(entry.winRate.rounded()))%")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(entry.winRate >= 50 ? Theme.win : Theme.loss)

        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 4) {
                    TagChip(text: entry.tag)
                    HStack(spacing: 8) { record; percentage }
                }
            } else {
                HStack {
                    TagChip(text: entry.tag)
                    Spacer(minLength: 6)
                    record
                    percentage.frame(width: winRateColumnWidth, alignment: .trailing)
                }
            }
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Champions

    /// Every champion played, most played first: games, record, win rate and
    /// KDA on one row — op.gg's champion table — instead of a play-count chart
    /// and a win-rate list repeating the same champions.
    private var championRecords: [ChampionRecord] {
        Dictionary(grouping: leagueMatches) { $0.leagueStats?.champion ?? "Unknown" }
            .map { champion, games in
                let lines = games.compactMap(\.leagueStats)
                let kda = Double(lines.map { $0.kills + $0.assists }.reduce(0, +))
                    / Double(max(lines.map(\.deaths).reduce(0, +), 1))
                return ChampionRecord(champion: champion, games: games.count, wins: games.filter(\.win).count, kda: kda)
            }
            .sorted { $0.games == $1.games ? $0.winRate > $1.winRate : $0.games > $1.games }
    }

    @ViewBuilder
    private var championTable: some View {
        ForEach(Array(championRecords.enumerated()), id: \.element.id) { index, entry in
            if index > 0 { Divider() }
            championRow(entry)
        }
    }

    private func championRow(_ entry: ChampionRecord) -> some View {
        let games = Text("\(entry.games)")
            .font(.caption.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
        let record = Text("\(entry.wins)W \(entry.games - entry.wins)L · \(String(format: "%.2f", entry.kda)) KDA")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)
        let percentage = Text("\(Int(entry.winRate.rounded()))%")
            .font(.subheadline.weight(.semibold).monospacedDigit())
            .foregroundStyle(entry.winRate >= 50 ? Theme.win : Theme.loss)

        return HStack(spacing: 10) {
            ChampionIconView(championName: entry.champion, size: listPortraitSize)
            VStack(alignment: .leading, spacing: 2) {
                Text(entry.champion).font(.subheadline)
                record
            }
            Spacer(minLength: 6)
            if !dynamicTypeSize.isAccessibilitySize {
                games.frame(width: countColumnWidth, alignment: .trailing)
            }
            percentage.frame(width: winRateColumnWidth, alignment: .trailing)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Charts

    /// One bar per game, newest last, coloured by result.
    ///
    /// The old version plotted all 50 games against a *date* axis with curve
    /// smoothing: several games on one evening piled into the same pixel while
    /// quiet days stretched into long meaningless slopes. Games are discrete
    /// events, so they get discrete bars on an evenly-spaced "game number"
    /// axis, with an average line for the trend.
    @ViewBuilder
    private var kdaChart: some View {
        let recent = Array(leagueMatches.suffix(20))
        let points = recent.enumerated().compactMap { index, match -> KDAGamePoint? in
            guard let stats = match.leagueStats else { return nil }
            return KDAGamePoint(index: index + 1, kda: stats.kda, win: match.win)
        }
        let average = points.isEmpty ? 0 : points.map(\.kda).reduce(0, +) / Double(points.count)

        Text("last \(points.count) · avg \(String(format: "%.1f", average))")
            .font(.caption.monospacedDigit())
            .foregroundStyle(.secondary)

        Chart {
            ForEach(points) { point in
                // A 0-KDA game still gets a visible stub: a missing bar
                // reads as a missing game, not a bad one.
                BarMark(
                    x: .value("Game", point.index),
                    y: .value("KDA", max(point.kda, 0.08)),
                    width: .fixed(9)
                )
                .foregroundStyle(point.win ? Color.green.gradient : Color.red.gradient)
                .cornerRadius(3)
            }
            RuleMark(y: .value("Average", average))
                .foregroundStyle(.secondary.opacity(0.5))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
                .annotation(position: .top, alignment: .leading) {
                    Text("avg").scaledFont(9).foregroundStyle(.secondary)
                }
        }
        .chartXAxis(.hidden)
        .chartYAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .frame(height: chartHeight)

        // One row with the caption pushed right, until the text is large enough
        // that the two would collide — then it wraps.
        let legend = legendDot(color: .green, label: "Win")
        let lossLegend = legendDot(color: .red, label: "Loss")
        let caption = Text("oldest → newest").scaledFont(9).foregroundStyle(.tertiary)
        if dynamicTypeSize.isAccessibilitySize {
            FlowLayout(spacing: 12) { legend; lossLegend; caption }
        } else {
            HStack(spacing: 12) {
                legend
                lossLegend
                Spacer()
                caption
            }
        }
    }

    private func legendDot(color: Color, label: String) -> some View {
        HStack(spacing: 4) {
            Circle().fill(color).frame(width: legendDotSize, height: legendDotSize)
            Text(label).scaledFont(10).foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var roleChart: some View {
        let grouped = Dictionary(grouping: leagueMatches) { $0.leagueStats?.role ?? "—" }
        let stats = grouped.map { role, matches -> RoleWinRate in
            let wins = matches.filter(\.win).count
            let rate = matches.isEmpty ? 0 : Double(wins) / Double(matches.count) * 100
            return RoleWinRate(role: role, games: matches.count, winRate: rate)
        }.sorted { $0.games > $1.games }

        Chart {
            ForEach(stats) { entry in
                // The game count rides on the label, so one lucky game can't
                // pass for a 100% role, and 0% reads as 0% rather than no bar.
                BarMark(x: .value("Role", "\(entry.role) (\(entry.games))"), y: .value("Win rate", entry.winRate))
                    .foregroundStyle(entry.winRate >= 50 ? Color.green.gradient : Color.red.gradient)
                    .cornerRadius(4)
                    .annotation(position: .top) {
                        Text("\(Int(entry.winRate.rounded()))%")
                            .font(.caption2.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
            }
            RuleMark(y: .value("Even", 50))
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: 0...100)
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .frame(height: tallChartHeight)
    }

    @ViewBuilder
    private var placementChart: some View {
        let points = tftMatches.compactMap { match -> PlacementPoint? in
            guard let stats = match.tftStats else { return nil }
            return PlacementPoint(date: match.timestamp, placement: stats.placement)
        }

        Text("Lower is better")
            .font(.caption)
            .foregroundStyle(.secondary)

        Chart {
            ForEach(points) { point in
                LineMark(x: .value("Date", point.date), y: .value("Placement", point.placement))
                    .foregroundStyle(chartAccent)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
                PointMark(x: .value("Date", point.date), y: .value("Placement", point.placement))
                    .foregroundStyle(chartAccent)
                    .symbolSize(20)
            }
            RuleMark(y: .value("Top 4", 4))
                .foregroundStyle(.secondary.opacity(0.4))
                .lineStyle(StrokeStyle(lineWidth: 1, dash: [4, 3]))
        }
        .chartYScale(domain: [8, 1])
        .chartXAxis {
            AxisMarks(values: .automatic(desiredCount: 4)) { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .chartYAxis {
            AxisMarks { _ in
                AxisGridLine().foregroundStyle(.quaternary)
                AxisValueLabel()
            }
        }
        .frame(height: tallChartHeight)
    }
}
