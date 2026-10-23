import SwiftUI

/// One player on the scoreboard, 掌盟-style: two dense lines so all ten
/// players fit on one screen, with runes, the named build and the detailed
/// numbers a tap away.
struct ScoreboardRowView: View {
    let participant: MatchParticipantSummary
    let match: Match
    var award: MatchAward?
    let region: RiotRegion?
    let platform: RiotPlatform?

    @State private var isExpanded = false
    @State private var panel: Panel = .runes
    /// Current solo rank, looked up on demand — Riot's match data carries no
    /// per-match tier, and it isn't the linked player's data to store.
    @State private var rank: RiotLeagueEntry?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .caption) private var portraitSize: CGFloat = 38
    @ScaledMetric(relativeTo: .caption2) private var loadoutSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption2) private var itemSize: CGFloat = 15
    @ScaledMetric(relativeTo: .caption2) private var rankIconSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption2) private var levelBadgeSize: CGFloat = 15

    private enum Panel { case runes, items, stats }

    /// Nil when an older API key imported the match: its ids no longer
    /// decrypt, and a saved game can be days old.
    private var currentPUUID: String? {
        match.importVersion == MatchImportService.currentDataVersion ? participant.puuid : nil
    }

    /// Where they placed out of ten — "4th", "第4" — in the reader's language.
    private static let ordinal: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Button {
                withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
            } label: {
                summary.contentShape(Rectangle())
            }
            .buttonStyle(PressableButtonStyle())
            .accessibilityValue(isExpanded ? "Expanded" : "Collapsed")
            .accessibilityHint(isExpanded ? "Hides details" : "Shows runes, items and stats")

            if isExpanded {
                details
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(.vertical, 6)
        .task(id: participant.puuid) {
            guard let platform, let puuid = currentPUUID else { return }
            rank = await RiotAPIClient.shared.soloRank(puuid: puuid, platform: platform)
        }
    }

    // MARK: - Summary

    private var summary: some View {
        HStack(spacing: 8) {
            portrait
            loadout
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 4) {
                    Text(participant.riotIdGameName)
                        .font(.caption.weight(participant.isYou ? .bold : .regular))
                        .foregroundStyle(participant.isYou ? Theme.accent : .primary)
                        .lineLimit(1)
                        .truncationMode(.tail)
                    if participant.isYou { badge("YOU", tint: Theme.accent) }
                    if let award { badge(award.text, tint: award.tint) }
                    Spacer(minLength: 4)
                    scoreLabel
                }
                HStack(spacing: 5) {
                    rankLabel
                    Text("\(participant.kills)/\(participant.deaths)/\(participant.assists)")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .fixedSize()
                        .accessibilityLabel("\(participant.kills) kills, \(participant.deaths) deaths, \(participant.assists) assists")
                    Spacer(minLength: 4)
                    if !dynamicTypeSize.isAccessibilitySize { items }
                }
                // At accessibility sizes the build needs a line of its own.
                if dynamicTypeSize.isAccessibilitySize { items }
            }
        }
        .accessibilityElement(children: .combine)
    }

    private var portrait: some View {
        ChampionIconView(championName: participant.champion, size: portraitSize)
            .overlay(alignment: .bottomTrailing) {
                if participant.champLevel > 0 {
                    Text("\(participant.champLevel)")
                        .scaledFont(8, weight: .bold)
                        .foregroundStyle(.white)
                        .frame(width: levelBadgeSize, height: levelBadgeSize)
                        .background(Circle().fill(.black.opacity(0.8)))
                        .offset(x: 3, y: 3)
                }
            }
    }

    /// Summoner spells beside the keystone and secondary tree, 2×2.
    private var loadout: some View {
        let spells = participant.summonerSpellIDs
        return Grid(horizontalSpacing: 2, verticalSpacing: 2) {
            GridRow {
                slot(spells.first.map { SpellIconView(spellID: $0, size: loadoutSize) })
                slot(participant.keystoneID == 0 ? nil : RuneIconView(runeID: participant.keystoneID, size: loadoutSize))
            }
            GridRow {
                slot(spells.dropFirst().first.map { SpellIconView(spellID: $0, size: loadoutSize) })
                slot(participant.subStyleID == 0 ? nil : RuneIconView(runeID: participant.subStyleID, size: loadoutSize))
            }
        }
    }

    @ViewBuilder
    private func slot<V: View>(_ view: V?) -> some View {
        if let view { view } else { Color.clear.frame(width: loadoutSize, height: loadoutSize) }
    }

    @ViewBuilder
    private var rankLabel: some View {
        if let rank {
            HStack(spacing: 1) {
                RankIconView(tier: rank.tier, size: rankIconSize)
                Text(rank.rank)
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
            .fixedSize()
        }
    }

    private var scoreLabel: some View {
        let score = PerformanceScore.compute(for: participant, in: match)
        return HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(String(format: "%.1f", score))
                .font(.subheadline.weight(.bold).monospacedDigit())
                .foregroundStyle(PerformanceScore.color(for: score))
            if let place = PerformanceScore.rank(for: participant, in: match) {
                Text(Self.ordinal.string(from: NSNumber(value: place)) ?? "\(place)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
        }
        .fixedSize()
    }

    /// Display-only at this size; the Items panel is where an item can
    /// actually be inspected.
    private var items: some View {
        ItemSlots(items: participant.items, size: itemSize)
    }

    private func badge(_ text: String, tint: Color) -> some View {
        Text(text)
            .scaledFont(8, weight: .black)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(tint, in: RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
            .fixedSize()
    }

    // MARK: - Details

    private var details: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Details", selection: $panel) {
                Text("Runes").tag(Panel.runes)
                Text("Items").tag(Panel.items)
                Text("Stats").tag(Panel.stats)
            }
            .pickerStyle(.segmented)

            switch panel {
            case .runes:
                RuneListView(
                    primaryRuneIDs: participant.primaryRuneIDs,
                    secondaryRuneIDs: participant.secondaryRuneIDs,
                    primaryStyleID: participant.primaryStyleID,
                    subStyleID: participant.subStyleID,
                    statPerkIDs: participant.statPerkIDs
                )
            case .items:
                ItemBuildListView(items: participant.items)
            case .stats:
                statsGrid
            }

            if !participant.isYou, let region {
                NavigationLink {
                    PlayerProfileView(
                        puuid: currentPUUID,
                        riotIdGameName: participant.riotIdGameName,
                        riotIdTagline: participant.riotIdTagline,
                        region: region,
                        platform: platform
                    )
                } label: {
                    Label("View \(participant.riotIdGameName)'s profile", systemImage: "person.crop.circle")
                        .font(.subheadline.weight(.semibold))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Theme.accent.opacity(0.12), in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
                }
                .buttonStyle(PressableButtonStyle())
            }
        }
        .padding(12)
        .background(Theme.surfaceRaised, in: RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
    }

    private var statsGrid: some View {
        let killParticipation = Int(((match.killShare(of: participant) ?? 0) * 100).rounded())
        let minutes = match.minutes
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.flexible()), GridItem(.flexible())]
            : Array(repeating: GridItem(.flexible()), count: 4)

        return LazyVGrid(columns: columns, spacing: 10) {
            MiniStat(value: "\(killParticipation)%", label: "Kill share", weight: .semibold, spacing: 2)
            MiniStat(value: participant.damageDealtToChampions.formatted(), label: "Damage", weight: .semibold, spacing: 2)
            MiniStat(value: participant.damageTaken.formatted(), label: "Taken", weight: .semibold, spacing: 2)
            MiniStat(value: participant.goldEarned.formatted(), label: "Gold", weight: .semibold, spacing: 2)
            MiniStat(value: "\(participant.creepScore) (\(String(format: "%.1f", Double(participant.creepScore) / minutes)))", label: "Minions", weight: .semibold, spacing: 2)
            MiniStat(value: "\(participant.visionScore)", label: "Vision", weight: .semibold, spacing: 2)
            MiniStat(value: "\(participant.wardsPlaced)/\(participant.wardsKilled)", label: "Wards", weight: .semibold, spacing: 2)
            MiniStat(value: participant.totalHeal.formatted(), label: "Healing", weight: .semibold, spacing: 2)
        }
    }
}

/// Riot's item array is seven *fixed* slots — 0-5 the build, 6 the trinket,
/// 0 for empty — so slots are read by index, never compacted, which keeps
/// every row's trinket in the same column. Display-only.
struct ItemSlots: View {
    let items: [Int]
    let size: CGFloat
    var spacing: CGFloat = 2

    var body: some View {
        HStack(spacing: spacing) {
            ForEach(0..<7, id: \.self) { index in
                let item = index < items.count ? items[index] : 0
                if item != 0 {
                    ItemIconView(itemID: item, size: size, interactive: false)
                } else {
                    RoundedRectangle(cornerRadius: size * 0.2)
                        .fill(.secondary.opacity(0.08))
                        .frame(width: size, height: size)
                }
            }
        }
    }
}

/// A small number over its label: the scoreboard's stat panel and the match
/// screen's per-minute rates.
struct MiniStat: View {
    let value: String
    let label: String
    let weight: Font.Weight
    let spacing: CGFloat

    var body: some View {
        VStack(spacing: spacing) {
            Text(value)
                .font(.caption.weight(weight).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .scaledFont(9)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }
}

enum MatchAward {
    case mvp
    case svp

    var text: String { self == .mvp ? "MVP" : "SVP" }
    /// Carries white text, so the orange is darkened past the system one.
    var tint: Color { self == .mvp ? Theme.orange : .purple }

    /// The award `puuid` earned, given a match's `PerformanceScore.awards`.
    init?(puuid: String, awards: (mvp: String?, svp: String?)) {
        switch puuid {
        case awards.mvp: self = .mvp
        case awards.svp: self = .svp
        default: return nil
        }
    }
}
