import SwiftUI
import Charts

/// The top of the Stats tab as a bento grid: win rate, four per-game
/// averages against the rest of the lobby, the best champion, and the
/// highlights. Every number carries a line saying what it means, because the
/// people reading it don't all play. `matches` is oldest first.
struct StatsBento: View {
    let matches: [Match]

    typealias Row = (match: Match, me: MatchParticipantSummary)

    var body: some View {
        let rows = matches.compactMap { match in match.focusParticipant.map { (match: match, me: $0) } }
        let metrics = metrics(rows)
        VStack(spacing: 12) {
            WinRateHero(matches: matches)
            // Grid rather than LazyVGrid so both tiles in a row share a height.
            Grid(horizontalSpacing: 12, verticalSpacing: 12) {
                GridRow { ForEach(metrics.prefix(2)) { MetricTile(metric: $0) } }
                GridRow { ForEach(metrics.dropFirst(2)) { MetricTile(metric: $0) } }
            }
            if let best = bestChampion {
                BestChampionCard(record: best)
            }
            HighlightsCard(rows: rows)
        }
    }

    // MARK: - Metrics

    private func metrics(_ rows: [Row]) -> [Metric] {
        guard !rows.isEmpty else { return [] }
        func average(_ values: [Double]) -> Double { values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count) }
        let others = rows.flatMap { row in row.match.participants.filter { $0.puuid != row.me.puuid }.map { (row.match, $0) } }
        func perMinute(_ key: KeyPath<MatchParticipantSummary, Int>) -> (series: [Double], lobby: Double) {
            (rows.map { Double($0.me[keyPath: key]) / $0.match.minutes },
             average(others.map { Double($0.1[keyPath: key]) / $0.0.minutes }))
        }

        // Totals over totals, the same rule as the summary card.
        let kda = FriendComparisonService.aggregate(rows.map(\.match)).kda
        let lobbyKDA = Double(others.map { $0.1.kills + $0.1.assists }.reduce(0, +))
            / Double(max(others.map(\.1.deaths).reduce(0, +), 1))
        // Farming is only fair against the lane opponent — a support drags
        // the lobby average down — the same comparison the AI card makes.
        let opponentCS = average(rows.compactMap { row in
            row.match.laneOpponent(of: row.me).map { Double($0.creepScore) / row.match.minutes }
        })
        let cs = rows.map { Double($0.me.creepScore) / $0.match.minutes }
        let damage = perMinute(\.damageDealtToChampions)
        let vision = perMinute(\.visionScore)

        return [
            Metric(title: "KDA ratio", icon: "bolt.fill", explain: "Takedowns per death",
                   value: kda, baseline: lobbyKDA, baselineLabel: "lobby",
                   series: rows.map(\.me.kda), digits: 2, valueTint: Theme.kdaColor(kda)),
            Metric(title: "Minions / min", icon: "leaf.fill", explain: "Main source of gold",
                   value: average(cs), baseline: opponentCS > 0 ? opponentCS : nil, baselineLabel: "opponent",
                   series: cs, digits: 1),
            Metric(title: "Damage / min", icon: "burst.fill", explain: "Dealt to enemy champions",
                   value: average(damage.series), baseline: damage.lobby, baselineLabel: "lobby",
                   series: damage.series, digits: 0),
            Metric(title: "Vision / min", icon: "eye.fill", explain: "Map revealed with wards",
                   value: average(vision.series), baseline: vision.lobby, baselineLabel: "lobby",
                   series: vision.series, digits: 1)
        ]
    }

    // MARK: - Best champion

    /// Best win rate over at least three games; the most played when nothing
    /// has three yet.
    private var bestChampion: ChampionRecord? {
        let records = ChampionRecord.records(from: matches)
        let qualified = records.filter { $0.games >= 3 }
        if !qualified.isEmpty {
            return qualified.max { ($0.winRate, $0.games) < ($1.winRate, $1.games) }
        }
        return records.max { $0.games < $1.games }
    }
}

// MARK: - Pieces

/// One champion's record across a set of League games.
struct ChampionRecord: Identifiable {
    let champion: String
    let games: Int
    let wins: Int
    let kda: Double
    var id: String { champion }
    var winRate: Double { games == 0 ? 0 : Double(wins) / Double(games) * 100 }

    /// `matches` are League games.
    static func records(from matches: [Match]) -> [ChampionRecord] {
        Dictionary(grouping: matches) { $0.leagueStats?.champion ?? "" }
            .map { champion, games in
                ChampionRecord(
                    champion: champion,
                    games: games.count,
                    wins: games.filter(\.win).count,
                    kda: FriendComparisonService.aggregate(games).kda
                )
            }
    }
}

private struct Metric: Identifiable {
    let title: String
    let icon: String
    let explain: String
    let value: Double
    let baseline: Double?
    let baselineLabel: String
    let series: [Double]
    let digits: Int
    var valueTint: Color = .primary
    var id: String { title }

    func format(_ number: Double) -> String { String(format: "%.\(digits)f", number) }
}

/// Win-rate ring, record, current streak, and the last ten results.
private struct WinRateHero: View {
    let matches: [Match]

    @ScaledMetric(relativeTo: .title) private var ringSize: CGFloat = 104

    var body: some View {
        let wins = matches.filter(\.win).count
        let rate = matches.isEmpty ? 0 : Double(wins) / Double(matches.count)
        let tint = rate >= 0.5 ? Theme.winBright : Theme.lossBright
        let recent = Array(matches.suffix(10))

        VStack(alignment: .leading, spacing: 16) {
            HStack(spacing: 20) {
                ZStack {
                    Circle().stroke(.white.opacity(0.2), lineWidth: 11)
                    Circle()
                        .trim(from: 0, to: rate)
                        .stroke(tint.gradient, style: StrokeStyle(lineWidth: 11, lineCap: .round))
                        .rotationEffect(.degrees(-90))
                    VStack(spacing: 0) {
                        Text("\(Int((rate * 100).rounded()))%")
                            .font(.title2.weight(.heavy).monospacedDigit())
                        Text("WIN RATE")
                            .scaledFont(8, weight: .bold)
                            .tracking(0.5)
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: ringSize, height: ringSize)

                VStack(alignment: .leading, spacing: 6) {
                    Text("\(wins)W – \(matches.count - wins)L")
                        .font(.title3.weight(.bold).monospacedDigit())
                    Text(rate > 0.5 ? "Wins more than half of games" : rate < 0.5 ? "Wins less than half of games" : "Wins exactly half of games")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let streak {
                        Label(streak.text, systemImage: streak.won ? "flame.fill" : "snowflake")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(streak.won ? Theme.goldOnDark : .white)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(.black.opacity(0.2), in: Capsule())
                    }
                }
                Spacer(minLength: 0)
            }

            if recent.count > 1 {
                VStack(alignment: .leading, spacing: 6) {
                    Text("LAST \(recent.count) GAMES · OLDEST → NEWEST")
                        .scaledFont(9, weight: .semibold)
                        .tracking(0.5)
                        .foregroundStyle(.secondary)
                    ResultStrip(matches: recent, win: Theme.winBright, loss: Theme.lossBright, spacing: 4)
                        .frame(height: 22)
                }
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Last \(recent.count) games: \(recent.filter(\.win).count) wins")
            }
        }
        // The one gradient card on the page: the headline number.
        .padding(Theme.cardPadding)
        .background(Theme.accentGradient)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .shadow(color: Theme.accent.opacity(0.3), radius: 14, y: 6)
        .environment(\.colorScheme, .dark)
    }

    /// The current run of identical results, newest back; nothing under two.
    private var streak: (text: String, won: Bool)? {
        guard let last = matches.last else { return nil }
        let run = matches.reversed().prefix { $0.win == last.win }.count
        guard run >= 2 else { return nil }
        return ("\(run)-game \(last.win ? "win" : "losing") streak", last.win)
    }
}

/// One average, how it compares, and its recent trend.
private struct MetricTile: View {
    let metric: Metric

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(metric.title, systemImage: metric.icon)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
            Text(metric.format(metric.value))
                .font(.title2.weight(.bold).monospacedDigit())
                .foregroundStyle(metric.valueTint)
            comparison
            sparkline
            Text(metric.explain)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(padding: 14)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var comparison: some View {
        if let baseline = metric.baseline, baseline > 0 {
            let change = (metric.value - baseline) / baseline
            // Within 5% reads as level, not as better or worse.
            let (icon, tint): (String, Color) = abs(change) < 0.05 ? ("equal", .secondary)
                : change > 0 ? ("arrow.up.right", Theme.win) : ("arrow.down.right", Theme.loss)
            HStack(spacing: 3) {
                Image(systemName: icon).fontWeight(.bold)
                Text("\(metric.baselineLabel) \(metric.format(baseline))")
            }
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(tint)
        }
    }

    /// The last 20 games, oldest to newest.
    @ViewBuilder
    private var sparkline: some View {
        let points = Array(metric.series.suffix(20).enumerated())
        if points.count < 2 {
            Text("Trend line after 2 games")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .frame(maxWidth: .infinity, minHeight: 34, alignment: .leading)
        } else {
            sparklineChart(points)
        }
    }

    private func sparklineChart(_ points: [(offset: Int, element: Double)]) -> some View {
        Chart {
            ForEach(points, id: \.offset) { index, value in
                AreaMark(x: .value("Game", index), y: .value(metric.title, value))
                    .foregroundStyle(LinearGradient(colors: [Theme.chart.opacity(0.35), .clear], startPoint: .top, endPoint: .bottom))
                    .interpolationMethod(.catmullRom)
                LineMark(x: .value("Game", index), y: .value(metric.title, value))
                    .foregroundStyle(Theme.chart)
                    .lineStyle(StrokeStyle(lineWidth: 2, lineCap: .round))
                    .interpolationMethod(.catmullRom)
            }
        }
        .chartXAxis(.hidden)
        .chartYAxis(.hidden)
        .frame(height: 34)
        .accessibilityHidden(true)
    }
}

/// The champion the player does best on, over its splash art.
private struct BestChampionCard: View {
    let record: ChampionRecord

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("BEST CHAMPION")
                .scaledFont(10, weight: .bold)
                .tracking(0.8)
                .foregroundStyle(Theme.goldOnDark)
            Text(record.champion)
                .font(.title.weight(.heavy))
            Text("\(Int(record.winRate.rounded()))% win rate · \(record.games) games · \(String(format: "%.2f", record.kda)) KDA")
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .foregroundStyle(.secondary)
        }
        .padding(Theme.cardPadding)
        .frame(maxWidth: .infinity, minHeight: 150, alignment: .bottomLeading)
        .background { ChampionSplash(champion: record.champion) }
        .environment(\.colorScheme, .dark)
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous).strokeBorder(Theme.goldOnDark.opacity(0.3), lineWidth: 1))
        .cardShadow()
        .accessibilityElement(children: .combine)
    }
}

/// Awards and rare moments, counted.
private struct HighlightsCard: View {
    let rows: [StatsBento.Row]

    var body: some View {
        let awards = rows.map { MatchAward(puuid: $0.me.puuid, awards: PerformanceScore.awards(in: $0.match)) }
        let mvp = awards.filter { $0 == .mvp }.count
        let svp = awards.filter { $0 == .svp }.count
        let lines = rows.compactMap(\.match.leagueStats)
        let firstBlood = lines.isEmpty ? 0 : Double(lines.filter(\.firstBloodKill).count) / Double(lines.count) * 100

        // Only what happened: a row of 0 triple / quadra / penta kills read
        // as broken, and the last round already dropped zero stats elsewhere.
        let firstBloodPercent = Int(firstBlood.rounded())
        let counters: [Counter] = [
            Counter(count: mvp, value: "\(mvp)", label: "MVP", icon: "crown.fill", tint: MatchAward.mvp.tint),
            Counter(count: svp, value: "\(svp)", label: "SVP", icon: "medal.fill", tint: MatchAward.svp.tint),
            Counter(count: firstBloodPercent, value: "\(firstBloodPercent)%", label: "First blood", icon: "drop.fill", tint: Theme.poor),
            Counter(count: lines.map(\.tripleKills).reduce(0, +), label: "Triple kills", icon: "flame", tint: Theme.fair),
            Counter(count: lines.map(\.quadraKills).reduce(0, +), label: "Quadra kills", icon: "flame.fill", tint: Theme.orange),
            Counter(count: lines.map(\.pentaKills).reduce(0, +), label: "Pentakills", icon: "flame.circle.fill", tint: Theme.poor)
        ].filter { $0.count > 0 }

        if !counters.isEmpty {
            VStack(alignment: .leading, spacing: 12) {
                Text("Highlights").font(.headline)
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    ForEach(Array(stride(from: 0, to: counters.count, by: 3)), id: \.self) { start in
                        GridRow {
                            ForEach(counters[start..<min(start + 3, counters.count)], id: \.label) {
                                counter($0.value, $0.label, $0.icon, $0.tint)
                            }
                        }
                    }
                }
                let shown = Set(counters.map(\.label))
                let notes = [("MVP", "MVP: best rating on the winning team."),
                             ("SVP", "SVP: best on the losing team."),
                             ("First blood", "First blood: the game's first kill.")]
                    .filter { shown.contains($0.0) }.map(\.1)
                if !notes.isEmpty {
                    Text(notes.joined(separator: " "))
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .cardSurface()
        }
    }

    private struct Counter {
        let count: Int
        var value: String
        let label: String
        let icon: String
        let tint: Color

        init(count: Int, value: String? = nil, label: String, icon: String, tint: Color) {
            self.count = count
            self.value = value ?? "\(count)"
            self.label = label
            self.icon = icon
            self.tint = tint
        }
    }

    private func counter(_ value: String, _ label: String, _ icon: String, _ tint: Color) -> some View {
        VStack(spacing: 3) {
            Image(systemName: icon)
                .font(.subheadline)
                .foregroundStyle(tint)
                .frame(height: 20)
            Text(value)
                .font(.headline.monospacedDigit())
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 10)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
        .accessibilityElement(children: .combine)
    }
}

/// Results as a row of bars, oldest on the left.
struct ResultStrip: View {
    let matches: [Match]
    var win = Theme.win
    var loss = Theme.loss
    var spacing: CGFloat = 2
    var maxBarWidth: CGFloat = .infinity

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(Array(matches.enumerated()), id: \.offset) { _, match in
                RoundedRectangle(cornerRadius: spacing, style: .continuous)
                    .fill(match.win ? win : loss)
                    .frame(maxWidth: maxBarWidth)
            }
        }
    }
}
