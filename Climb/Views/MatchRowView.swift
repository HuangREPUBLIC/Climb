import SwiftUI

/// One game in a match list, op.gg-style: the outcome as a colour bar, the
/// loadout beside the portrait, KDA and score on top, the build underneath.
struct MatchRowView: View {
    let match: Match

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .subheadline) private var rawPortraitSize: CGFloat = 44
    private var portraitSize: CGFloat { rawPortraitSize.capped(at: 72) }
    @ScaledMetric(relativeTo: .caption2) private var loadoutSize: CGFloat = 20
    @ScaledMetric(relativeTo: .caption2) private var itemSize: CGFloat = 20

    private var me: MatchParticipantSummary? { match.focusParticipant }

    private var won: Bool {
        if let tft = match.tftStats { return tft.placement <= 4 }
        return match.win
    }
    private var resultColor: Color { won ? Theme.win : Theme.loss }

    var body: some View {
        HStack(alignment: .center, spacing: 10) {
            portrait
            if let me { loadout(me) }

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    headline
                    if let accolade = accolades.first { accoladeChip(accolade) }
                    Spacer(minLength: 4)
                    scoreChip
                }

                HStack(spacing: 4) {
                    Text("\(Text(outcomeText).foregroundStyle(resultColor).fontWeight(.semibold)) · \(match.queueType)")
                        .lineLimit(1)
                    Spacer(minLength: 6)
                    Text(match.timestamp, format: .relative(presentation: .numeric, unitsStyle: .abbreviated))
                        .fixedSize()
                }
                .font(.caption)
                .foregroundStyle(.secondary)

                HStack(spacing: 2) {
                    if let stats = match.leagueStats {
                        itemStrip(stats.items)
                    } else if let tft = match.tftStats {
                        Text(tft.traits.prefix(3).joined(separator: " · "))
                            .lineLimit(1)
                    }
                    Spacer(minLength: 6)
                    Text(durationText)
                        .monospacedDigit()
                        .fixedSize()
                }
                .font(.caption2)
                .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
        .padding(.leading, 12)
        .background(alignment: .leading) {
            Capsule().fill(resultColor).frame(width: 4)
        }
        .accessibilityElement(children: .combine)
    }

    // MARK: - Pieces

    @ViewBuilder
    private var portrait: some View {
        if let stats = match.leagueStats {
            ChampionIconView(championName: stats.champion, size: portraitSize)
        } else if let tft = match.tftStats {
            RoundedRectangle(cornerRadius: portraitSize * 0.22)
                .fill(resultColor.opacity(0.15))
                .frame(width: portraitSize, height: portraitSize)
                .overlay {
                    Text("#\(tft.placement)")
                        .font(.headline)
                        .foregroundStyle(resultColor)
                }
        }
    }

    /// Summoner spells over the keystone and secondary tree, the way op.gg
    /// and the client both draw a loadout.
    private func loadout(_ player: MatchParticipantSummary) -> some View {
        let spells = player.summonerSpellIDs
        return Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                cell(spells.first.map { SpellIconView(spellID: $0, size: loadoutSize) })
                cell(player.keystoneID == 0 ? nil : RuneIconView(runeID: player.keystoneID, size: loadoutSize))
            }
            GridRow {
                cell(spells.dropFirst().first.map { SpellIconView(spellID: $0, size: loadoutSize) })
                cell(player.subStyleID == 0 ? nil : RuneIconView(runeID: player.subStyleID, size: loadoutSize))
            }
        }
    }

    /// A missing spell or rune keeps its cell, so nothing shifts columns.
    @ViewBuilder
    private func cell<V: View>(_ view: V?) -> some View {
        if let view { view } else { Color.clear.frame(width: loadoutSize, height: loadoutSize) }
    }

    @ViewBuilder
    private var headline: some View {
        if let stats = match.leagueStats {
            let slash = Text(" / ").foregroundStyle(.tertiary)
            Text("\(stats.kills)\(slash)\(Text("\(stats.deaths)").foregroundStyle(Theme.loss))\(slash)\(stats.assists)")
                .font(.subheadline.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .fixedSize(horizontal: !dynamicTypeSize.isAccessibilitySize, vertical: false)
                .accessibilityLabel("\(stats.kills) kills, \(stats.deaths) deaths, \(stats.assists) assists")
        } else if let tft = match.tftStats {
            Text("Level \(tft.level)")
                .font(.subheadline.weight(.bold))
        }
    }

    /// The score, with MVP / SVP beside it when the player earned one.
    @ViewBuilder
    private var scoreChip: some View {
        if let score = PerformanceScore.compute(for: match) {
            let awards = PerformanceScore.awards(in: match)
            let award: MatchAward? = me.flatMap {
                $0.puuid == awards.mvp ? .mvp : $0.puuid == awards.svp ? .svp : nil
            }
            HStack(spacing: 4) {
                if let award {
                    Text(award.text)
                        .scaledFont(9, weight: .black)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 1.5)
                        .background(award.tint, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
                Text(String(format: "%.1f", score))
                    .font(.caption.weight(.bold).monospacedDigit())
                    .foregroundStyle(PerformanceScore.color(for: score))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(PerformanceScore.color(for: score).opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            }
            .fixedSize()
        }
    }

    /// Seven fixed slots — build 0-5, trinket 6 — read by index so a
    /// half-finished build never slides the trinket into the build.
    private func itemStrip(_ items: [Int]) -> some View {
        HStack(spacing: 2) {
            ForEach(0..<7, id: \.self) { index in
                let item = index < items.count ? items[index] : 0
                if item != 0 {
                    ItemIconView(itemID: item, size: itemSize, interactive: false)
                } else {
                    RoundedRectangle(cornerRadius: itemSize * 0.2)
                        .fill(.secondary.opacity(0.08))
                        .frame(width: itemSize, height: itemSize)
                }
            }
        }
    }

    private var outcomeText: String {
        if match.tftStats != nil { return won ? "Top 4" : "Bottom 4" }
        return won ? "Victory" : "Defeat"
    }

    private var durationText: String {
        String(format: "%d:%02d", match.gameDurationSeconds / 60, match.gameDurationSeconds % 60)
    }

    // MARK: - Accolades

    /// At most one badge, and only for something genuinely uncommon.
    ///
    /// A double kill happens most games, and a tank main leads damage taken
    /// nearly every game — badges on every row stop meaning anything. So
    /// multi-kills start at triple, "most tanked" needs a real margin over the
    /// runner-up, and only the single most impressive one is shown.
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

        guard let me else { return [] }
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
}
