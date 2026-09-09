import SwiftUI

struct MatchRowView: View {
    let match: Match
    /// The account's current rank, shown as the "模式 | 段位" context line.
    /// Riot's match data carries no per-match tier, so this is today's rank
    /// rather than the rank held when the game was played.
    var rankLabel: String?
    /// List/NavigationLink already draws its own disclosure chevron;
    /// only draw ours when this row lives in a plain (non-List) container.
    var showsChevron: Bool = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .subheadline) private var rawPortraitSize: CGFloat = 44
    private var portraitSize: CGFloat { rawPortraitSize.capped(at: 72) }

    private var resultColor: Color {
        if let tftStats = match.tftStats { return tftStats.placement <= 4 ? .green : .red }
        return match.win ? .green : .red
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            if let stats = match.leagueStats {
                ChampionIconView(championName: stats.champion, size: portraitSize)
            } else if let stats = match.tftStats {
                placementBadge(stats.placement)
            } else {
                Image(systemName: match.game.systemImageName)
                    .font(.title3)
                    .foregroundStyle(resultColor)
                    .frame(width: portraitSize, height: portraitSize)
            }

            // Two rows: outcome + KDA/score on the first, context + timestamp
            // on the second. The result colour lives in the word itself, so
            // the decorative bar that used to sit on the left is gone.
            VStack(alignment: .leading, spacing: 4) {
                // Outcome, KDA and score share one line while they fit. Every
                // piece is `fixedSize`, so past that they would run off the
                // edge rather than truncate — they stack instead.
                if dynamicTypeSize.isAccessibilitySize {
                    // Nothing here is `fixedSize` in this branch: at these
                    // sizes a fixed KDA plus the chip is wider than the row.
                    VStack(alignment: .leading, spacing: 4) {
                        outcomeLabel
                        if let tag = accolades.first { accoladeChip(tag) }
                        scoreLine
                        scoreChip
                    }
                    .fixedSize(horizontal: false, vertical: true)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        outcomeLabel
                        if let tag = accolades.first { accoladeChip(tag) }
                        Spacer(minLength: 4)
                        scoreLine
                        scoreChip
                    }
                }

                // One line, mode/rank truncating and the timestamp holding the
                // trailing edge. Only at accessibility sizes, where truncating
                // would leave a few characters, do the two stack.
                Group {
                    if dynamicTypeSize.isAccessibilitySize {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(subtitleText)
                            Text(match.timestamp, format: Self.timestampFormat)
                        }
                    } else {
                        HStack(spacing: 5) {
                            Text(subtitleText)
                                .lineLimit(1)
                                .truncationMode(.tail)
                            Spacer(minLength: 6)
                            Text(match.timestamp, format: Self.timestampFormat)
                                .fixedSize()
                        }
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
            }

            if showsChevron {
                Image(systemName: "chevron.right")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
        }
        .padding(.vertical, 5)
    }

    @ViewBuilder
    private var outcomeLabel: some View {
        let text = match.tftStats == nil
            ? Text(match.win ? "Victory" : "Defeat").foregroundStyle(resultColor)
            : Text(titleText)
        text
            .font(.subheadline.weight(.bold))
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }

    @ViewBuilder
    private var scoreLine: some View {
        if let stats = match.leagueStats {
            if dynamicTypeSize.isAccessibilitySize {
                // One concatenated `Text` here, not five separate ones: five
                // views each shrink on their own, so the kill count truncates
                // to "…" while the assists stay full size.
                (Text("\(stats.kills)")
                    + Text("/").foregroundStyle(.tertiary)
                    + Text("\(stats.deaths)").foregroundStyle(.red)
                    + Text("/").foregroundStyle(.tertiary)
                    + Text("\(stats.assists)"))
                    .font(.subheadline.weight(.semibold).monospacedDigit())
                    .lineLimit(1)
                    .minimumScaleFactor(0.6)
                    .accessibilityLabel("\(stats.kills) kills, \(stats.deaths) deaths, \(stats.assists) assists")
            } else {
                HStack(spacing: 2) {
                    Text("\(stats.kills)")
                    Text("/").foregroundStyle(.tertiary)
                    Text("\(stats.deaths)").foregroundStyle(.red)
                    Text("/").foregroundStyle(.tertiary)
                    Text("\(stats.assists)")
                }
                .font(.subheadline.weight(.semibold).monospacedDigit())
                .fixedSize()
                .accessibilityElement(children: .combine)
                .accessibilityLabel("\(stats.kills) kills, \(stats.deaths) deaths, \(stats.assists) assists")
            }
        } else if let stats = match.tftStats {
            Text("Lv \(stats.level)")
                .font(.subheadline.weight(.semibold))
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        }
    }

    @ViewBuilder
    private var scoreChip: some View {
        if let score = PerformanceScore.compute(for: match) {
            Text(String(format: "%.1f", score))
                .font(.caption.weight(.bold).monospacedDigit())
                .foregroundStyle(PerformanceScore.color(for: score))
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(PerformanceScore.color(for: score).opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
        }
    }

    /// Absolute time, since "4 days ago" tells you nothing about which of that
    /// evening's games this was.
    private static let timestampFormat = Date.FormatStyle()
        .month(.abbreviated)
        .day()
        .hour(.defaultDigits(amPM: .abbreviated))
        .minute()

    /// Mode plus rank, matching the reference app's "单双排 | 白银 IV" row.
    /// The champion name is dropped because the portrait already says it.
    private var subtitleText: String {
        var parts: [String] = [match.queueType]
        if let rankLabel, !rankLabel.isEmpty {
            parts.append(rankLabel)
        }
        return parts.joined(separator: " | ")
    }

    /// At most one badge, and only for something genuinely uncommon.
    ///
    /// A double kill happens most games, and a tank main leads damage-taken
    /// nearly every game — badges that appear on every row stop meaning
    /// anything. So multi-kills start at triple, "most tanked" requires a real
    /// margin over the runner-up rather than merely topping the list, and only
    /// the single most impressive one is shown.
    struct Accolade: Hashable {
        let text: String
        let icon: String
    }

    private var accolades: [Accolade] {
        guard let stats = match.leagueStats else { return [] }

        if stats.pentaKills > 0 { return [Accolade(text: "Pentakill", icon: "flame.fill")] }
        if stats.quadraKills > 0 { return [Accolade(text: "Quadra Kill", icon: "flame.fill")] }
        if stats.tripleKills > 0 { return [Accolade(text: "Triple Kill", icon: "flame.fill")] }
        if stats.firstBloodKill { return [Accolade(text: "First Blood", icon: "drop.fill")] }

        guard let me = match.participants.first(where: \.isLinkedPlayer) else { return [] }

        if leads(\.damageDealtToChampions, me: me, byMargin: 1.15) {
            return [Accolade(text: "Most Damage", icon: "burst.fill")]
        }
        if leads(\.damageTaken, me: me, byMargin: 1.25) {
            return [Accolade(text: "Most Tanked", icon: "shield.fill")]
        }
        return []
    }

    /// True when the linked player tops every other player on `metric` by at
    /// least `margin` (1.15 = 15% clear of second place).
    private func leads(
        _ metric: KeyPath<MatchParticipantSummary, Int>,
        me: MatchParticipantSummary,
        byMargin margin: Double
    ) -> Bool {
        let mine = me[keyPath: metric]
        guard mine > 0 else { return false }
        let runnerUp = match.participants
            .filter { $0.puuid != me.puuid }
            .map { $0[keyPath: metric] }
            .max() ?? 0
        return Double(mine) >= Double(runnerUp) * margin
    }

    private func accoladeChip(_ accolade: Accolade) -> some View {
        HStack(spacing: 3) {
            Image(systemName: accolade.icon)
                .scaledFont(8, weight: .bold)
            Text(accolade.text)
                .scaledFont(9, weight: .bold)
        }
        .foregroundStyle(.orange)
        .padding(.horizontal, 5)
        .padding(.vertical, 2)
        .background(Color.orange.opacity(0.15))
        .clipShape(Capsule())
        .lineLimit(1)
        .minimumScaleFactor(0.6)
        .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
    }

    private var titleText: String {
        if let stats = match.leagueStats { return stats.champion }
        if match.tftStats != nil { return "Teamfight Tactics" }
        return match.game.shortName
    }

    private func placementBadge(_ placement: Int) -> some View {
        RoundedRectangle(cornerRadius: portraitSize * 0.22)
            .fill(placement <= 4 ? Color.green.opacity(0.15) : Color.red.opacity(0.15))
            .frame(width: portraitSize, height: portraitSize)
            .overlay {
                Text("#\(placement)")
                    .font(.headline)
                    .foregroundStyle(placement <= 4 ? .green : .red)
            }
    }
}
