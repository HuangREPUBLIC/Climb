import SwiftUI

/// One lane pairing on the scoreboard, laid out like the reference app:
/// portrait with level, runes/summoners beside the name, items underneath,
/// and the detailed stat comparison hidden behind a chevron so the page
/// stays scannable until you ask for the numbers.
struct LaneMatchupRowView: View {
    let role: String
    let left: MatchParticipantSummary?
    let right: MatchParticipantSummary?
    let region: RiotRegion?
    let platform: RiotPlatform?
    let match: Match
    var mvpPUUID: String?
    var svpPUUID: String?

    @State private var isExpanded = false
    @State private var expandedPanel: ExpandedPanel = .loadout

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .caption2) private var markerSize: CGFloat = 30
    @ScaledMetric(relativeTo: .caption2) private var markerIconSize: CGFloat = 18
    @ScaledMetric(relativeTo: .caption2) private var dividerHeight: CGFloat = 46
    @ScaledMetric(relativeTo: .caption) private var miniStatMinWidth: CGFloat = 54
    @ScaledMetric(relativeTo: .caption2) private var barHeight: CGFloat = 5

    /// Two player blocks only fit side by side while the text is small. Past
    /// the accessibility sizes each one needs the full width, so the pairing
    /// stacks with the lane marker between the two players instead.
    private var isStacked: Bool { dynamicTypeSize.isAccessibilitySize }

    enum ExpandedPanel {
        case loadout
        case items
        case stats
    }

    var body: some View {
        VStack(spacing: 8) {
            // The lane icon sits between the two players rather than as a
            // text heading above them — it marks the pairing, which is what
            // the row is actually about.
            if isStacked {
                VStack(spacing: 10) {
                    playerBlock(left, alignment: .leading)
                    positionMarker
                    playerBlock(right, alignment: .trailing)
                }
            } else {
                HStack(alignment: .top, spacing: 4) {
                    playerBlock(left, alignment: .leading)
                    positionMarker
                    playerBlock(right, alignment: .trailing)
                }
            }

            if left != nil, right != nil {
                Button {
                    withAnimation(.snappy(duration: 0.25)) { isExpanded.toggle() }
                } label: {
                    Image(systemName: "chevron.down")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.secondary)
                        .rotationEffect(.degrees(isExpanded ? 180 : 0))
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                        .contentShape(Rectangle())
                }
                .buttonStyle(PressableButtonStyle())

                if isExpanded, let left, let right {
                    expandedComparison(left: left, right: right)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                }
            }
        }
        .padding(.vertical, 8)
    }

    /// Stacked, both blocks read top-down, so the trailing block's mirrored
    /// arrangement (info on the left of the portrait) would be wrong — every
    /// block leads.
    private func playerBlock(_ participant: MatchParticipantSummary?, alignment: HorizontalAlignment) -> some View {
        LaneMatchupPlayerBlock(
            participant: participant,
            alignment: isStacked ? .leading : alignment,
            region: region,
            platform: platform,
            match: match,
            award: award(for: participant)
        )
    }

    private var positionMarker: some View {
        ZStack {
            Circle()
                .fill(Color(.tertiarySystemGroupedBackground))
                .frame(width: markerSize, height: markerSize)
            if let url = ObjectiveIconService.positionURL(role: role) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Text(String(role.prefix(1)))
                            .font(.caption2.weight(.bold))
                            .foregroundStyle(.secondary)
                    }
                }
                .frame(width: markerIconSize, height: markerIconSize)
            } else {
                Text(String(role.prefix(1)))
                    .font(.caption2.weight(.bold))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.top, isStacked ? 0 : 12)
        .accessibilityLabel("\(role) lane")
    }

    private func award(for participant: MatchParticipantSummary?) -> MatchAward? {
        guard let participant else { return nil }
        if participant.puuid == mvpPUUID { return .mvp }
        if participant.puuid == svpPUUID { return .svp }
        return nil
    }

    // MARK: - Expanded detail

    /// Two panels behind a segmented switch, defaulting to the loadout —
    /// matching the reference app, where expanding a row shows runes first and
    /// the numbers are one tap away.
    @ViewBuilder
    private func expandedComparison(left: MatchParticipantSummary, right: MatchParticipantSummary) -> some View {
        VStack(spacing: 12) {
            Picker("", selection: $expandedPanel) {
                Text(usesAugments ? "Augments" : "Runes").tag(ExpandedPanel.loadout)
                Text("Items").tag(ExpandedPanel.items)
                Text("Stats").tag(ExpandedPanel.stats)
            }
            .pickerStyle(.segmented)
            .frame(maxWidth: 300)

            switch expandedPanel {
            case .loadout:
                loadoutPanel(left: left, right: right)
            case .items:
                itemsPanel(left: left, right: right)
            case .stats:
                statsPanel(left: left, right: right)
            }
        }
        .padding(.top, 4)
    }

    private var usesAugments: Bool {
        MatchImportService.usesAugments(queueId: match.queueId)
    }

    @ViewBuilder
    private func loadoutPanel(left: MatchParticipantSummary, right: MatchParticipantSummary) -> some View {
        if usesAugments {
            sideBySide {
                AugmentListView(ids: left.augmentIDs, alignment: .leading)
            } trailing: {
                AugmentListView(ids: right.augmentIDs, alignment: isStacked ? .leading : .trailing)
            }
        } else {
            sideBySide {
                RuneListView(
                    primaryRuneIDs: left.primaryRuneIDs,
                    secondaryRuneIDs: left.secondaryRuneIDs,
                    primaryStyleID: left.primaryStyleID,
                    subStyleID: left.subStyleID,
                    statPerkIDs: left.statPerkIDs,
                    alignment: .leading
                )
            } trailing: {
                RuneListView(
                    primaryRuneIDs: right.primaryRuneIDs,
                    secondaryRuneIDs: right.secondaryRuneIDs,
                    primaryStyleID: right.primaryStyleID,
                    subStyleID: right.subStyleID,
                    statPerkIDs: right.statPerkIDs,
                    alignment: isStacked ? .leading : .trailing
                )
            }
        }
    }

    /// Both builds named side by side. More useful than tapping one thumbnail
    /// at a time anyway: the question on a matchup row is "what did they buy
    /// that I didn't", which needs both lists visible at once.
    private func itemsPanel(left: MatchParticipantSummary, right: MatchParticipantSummary) -> some View {
        sideBySide {
            ItemBuildListView(items: left.items, alignment: .leading)
        } trailing: {
            ItemBuildListView(items: right.items, alignment: isStacked ? .leading : .trailing)
        }
    }

    /// The two-column comparison the expanded panels are built from — a row
    /// split by a divider normally, one column under the other once the text
    /// is too large for two columns to hold anything readable.
    @ViewBuilder
    private func sideBySide<L: View, T: View>(
        @ViewBuilder leading: () -> L,
        @ViewBuilder trailing: () -> T
    ) -> some View {
        if isStacked {
            VStack(alignment: .leading, spacing: 10) {
                leading()
                Divider()
                trailing()
            }
        } else {
            HStack(alignment: .top, spacing: 10) {
                leading()
                Divider()
                trailing()
            }
        }
    }

    private func statsPanel(left: MatchParticipantSummary, right: MatchParticipantSummary) -> some View {
        VStack(spacing: 12) {
            if isStacked {
                VStack(spacing: 10) {
                    miniStatGrid(for: left, alignment: .leading)
                    Divider()
                    miniStatGrid(for: right, alignment: .trailing)
                }
            } else {
                HStack(alignment: .top, spacing: 0) {
                    miniStatGrid(for: left, alignment: .leading)
                    Divider().frame(height: dividerHeight)
                    miniStatGrid(for: right, alignment: .trailing)
                }
            }

            VStack(spacing: 8) {
                comparisonBar(leftValue: left.damageDealtToChampions, rightValue: right.damageDealtToChampions, label: "Damage to champions")
                comparisonBar(leftValue: left.damageTaken, rightValue: right.damageTaken, label: "Damage taken")
                comparisonBar(leftValue: left.totalHeal, rightValue: right.totalHeal, label: "Healing")
                comparisonBar(leftValue: left.goldEarned, rightValue: right.goldEarned, label: "Gold")
                comparisonBar(leftValue: left.creepScore, rightValue: right.creepScore, label: "CS")
            }
        }
    }

    private func miniStatGrid(for participant: MatchParticipantSummary, alignment: HorizontalAlignment) -> some View {
        let tint: Color = alignment == .leading ? .blue : .red
        // Three columns, going adaptive only at accessibility sizes where a
        // third of the width can't hold "12/14" without truncating it.
        let columns = dynamicTypeSize.isAccessibilitySize
            ? [GridItem(.adaptive(minimum: miniStatMinWidth), spacing: 8)]
            : [GridItem(.flexible()), GridItem(.flexible()), GridItem(.flexible())]
        return LazyVGrid(columns: columns, spacing: 8) {
            miniStat("\(killParticipation(participant))%", "KP", tint: tint)
            miniStat("\(participant.wardsPlaced)/\(participant.wardsKilled)", "Wards", tint: tint)
            miniStat("\(participant.largestMultiKill)", "Multi", tint: tint)
            miniStat("\(participant.creepScore)", "CS", tint: tint)
            miniStat("\(participant.largestKillingSpree)", "Spree", tint: tint)
            miniStat("\(participant.turretKills)", "Turrets", tint: tint)
        }
        .padding(.horizontal, 6)
    }

    private func miniStat(_ value: String, _ label: String, tint: Color) -> some View {
        VStack(spacing: 1) {
            Text(value)
                .font(.caption.weight(.semibold).monospacedDigit())
                .foregroundStyle(tint)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(label)
                .scaledFont(8)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
    }

    private func killParticipation(_ participant: MatchParticipantSummary) -> Int {
        let teamKills = match.participants.filter { $0.teamId == participant.teamId }.map(\.kills).reduce(0, +)
        guard teamKills > 0 else { return 0 }
        return Int((Double(participant.kills + participant.assists) / Double(teamKills) * 100).rounded())
    }

    private func comparisonBar(leftValue: Int, rightValue: Int, label: String) -> some View {
        let total = max(leftValue + rightValue, 1)
        let leftFraction = CGFloat(leftValue) / CGFloat(total)
        return VStack(spacing: 3) {
            // One line while it fits; the label moves onto its own line once
            // the two numbers plus the label no longer share a row.
            ViewThatFits(in: .horizontal) {
                comparisonBarLabels(leftValue: leftValue, rightValue: rightValue, label: label, wraps: false)
                comparisonBarLabels(leftValue: leftValue, rightValue: rightValue, label: label, wraps: true)
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

    @ViewBuilder
    private func comparisonBarLabels(leftValue: Int, rightValue: Int, label: String, wraps: Bool) -> some View {
        let left = Text("\(leftValue)").font(.caption2.monospacedDigit()).foregroundStyle(.blue)
        let right = Text("\(rightValue)").font(.caption2.monospacedDigit()).foregroundStyle(.red)
        let title = Text(label).scaledFont(9).foregroundStyle(.secondary)

        if wraps {
            VStack(spacing: 2) {
                title.frame(maxWidth: .infinity, alignment: .leading)
                HStack { left; Spacer(); right }
            }
        } else {
            HStack {
                left
                Spacer(minLength: 6)
                title.lineLimit(1)
                Spacer(minLength: 6)
                right
            }
        }
    }
}

/// Where the player placed on the scoreboard, beside their score.
///
/// Deliberately neutral in colour: MVP and SVP already carry the "standout"
/// signal, and a second tinted badge saying the same thing in a different
/// language would compete with it. This one answers a different question —
/// out of ten, where did I actually come?
private struct RankBadge: View {
    let rank: Int

    /// `.ordinal` rather than a hand-rolled "st/nd/rd/th", which is wrong in
    /// every locale but English.
    private static let formatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.numberStyle = .ordinal
        return formatter
    }()

    var body: some View {
        Text(Self.formatter.string(from: NSNumber(value: rank)) ?? "\(rank)")
            // Tabular figures so the pill keeps its width as the rank changes
            // between rows instead of shifting the score beside it.
            .font(.caption2.weight(.semibold).monospacedDigit())
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 2)
            .background(Color.secondary.opacity(0.14), in: Capsule())
            .fixedSize()
            .accessibilityLabel("Rank \(rank)")
    }
}

enum MatchAward {
    case mvp
    case svp

    var text: String { self == .mvp ? "MVP" : "SVP" }
    var tint: Color { self == .mvp ? .orange : .purple }
}

private struct LaneMatchupPlayerBlock: View {
    let participant: MatchParticipantSummary?
    let alignment: HorizontalAlignment
    let region: RiotRegion?
    let platform: RiotPlatform?
    let match: Match
    let award: MatchAward?

    @State private var rankTier: String?
    @State private var rankDivision: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    /// Icons that sit beside text have to grow with it, or the row turns into
    /// giant type next to unchanged thumbnails.
    @ScaledMetric(relativeTo: .caption2) private var portraitSize: CGFloat = 46
    @ScaledMetric(relativeTo: .caption2) private var levelBadgeSize: CGFloat = 17
    @ScaledMetric(relativeTo: .caption2) private var portraitColumnWidth: CGFloat = 64
    @ScaledMetric(relativeTo: .caption2) private var itemCell: CGFloat = 16
    @ScaledMetric(relativeTo: .caption2) private var rankIconSize: CGFloat = 24

    var body: some View {
        if let participant {
            let content = blockContent(participant)

            if participant.isLinkedPlayer {
                content
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
                    content
                }
                .buttonStyle(PressableButtonStyle())
            } else {
                content
            }
        } else {
            Color.clear.frame(maxWidth: .infinity)
        }
    }

    /// Reference-app arrangement: a portrait column carrying the KDA and
    /// score, then an info column with the name, rank, and a grid whose first
    /// column is the keystone + summoner spells and the rest the items.
    private func blockContent(_ participant: MatchParticipantSummary) -> some View {
        let trailing = alignment == .trailing

        // Portrait, identity and loadout share a row while there is width for
        // it. At accessibility sizes the identity text alone fills that row,
        // so the loadout grid drops onto its own line underneath.
        return VStack(alignment: trailing ? .trailing : .leading, spacing: 6) {
            HStack(alignment: .top, spacing: 6) {
                if trailing { infoColumn(participant) }
                portraitColumn(participant)
                if !trailing { infoColumn(participant) }
            }
            if dynamicTypeSize.isAccessibilitySize {
                loadoutGrid(participant)
                    .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .task(id: participant.puuid) {
            guard let platform else { return }
            let rank = await RankLookupService.fetchSoloRank(puuid: participant.puuid, platform: platform)
            rankTier = rank?.tier
            rankDivision = rank?.division
        }
    }

    private func portraitColumn(_ participant: MatchParticipantSummary) -> some View {
        let score = PerformanceScore.compute(for: participant, in: match)
        return VStack(spacing: 5) {
            ChampionIconView(championName: participant.champion, size: portraitSize)
                .overlay(alignment: .bottomLeading) {
                    if participant.champLevel > 0 {
                        Text("\(participant.champLevel)")
                            .scaledFont(9, weight: .bold)
                            .foregroundStyle(.white)
                            .frame(width: levelBadgeSize, height: levelBadgeSize)
                            .background(Circle().fill(.black.opacity(0.8)))
                            .offset(x: -3, y: 3)
                    }
                }
                // The level badge hangs below the portrait's frame, so without
                // this the KDA line sits under the badge rather than under the
                // portrait and the whole column reads as cramped.
                .padding(.bottom, 6)

            Text("\(participant.kills)/\(participant.deaths)/\(participant.assists)")
                .font(.caption2.monospacedDigit())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            // Baseline-aligned rather than centre-aligned: the pill is shorter
            // than the score, and centring it leaves the two reading as though
            // they sit on different lines.
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                Text(String(format: "%.1f", score))
                    .font(.subheadline.weight(.bold).monospacedDigit())
                    .foregroundStyle(PerformanceScore.color(for: score))
                if let rank = PerformanceScore.rank(for: participant, in: match) {
                    RankBadge(rank: rank)
                }
            }
            .lineLimit(1)
            .minimumScaleFactor(0.7)
        }
        .frame(width: portraitColumnWidth)
        .accessibilityElement(children: .combine)
    }

    private func infoColumn(_ participant: MatchParticipantSummary) -> some View {
        let trailing = alignment == .trailing
        return VStack(alignment: trailing ? .trailing : .leading, spacing: 3) {
            HStack(spacing: 3) {
                if trailing, let award { awardBadge(award) }
                Text(participant.riotIdGameName)
                    .font(.caption2.weight(participant.isLinkedPlayer ? .bold : .regular))
                    .foregroundStyle(participant.isLinkedPlayer ? Color.accentColor : .primary)
                    .lineLimit(1)
                    .truncationMode(.tail)
                if participant.isLinkedPlayer {
                    Text("YOU")
                        .scaledFont(8, weight: .black)
                        .foregroundStyle(.white)
                        .padding(.horizontal, 3)
                        .padding(.vertical, 1)
                        .background(Color.accentColor)
                        .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
                }
                if !trailing, let award { awardBadge(award) }
            }

            HStack(spacing: 4) {
                if let rankTier {
                    RankIconView(tier: rankTier, size: rankIconSize)
                    Text(rankDivision ?? "")
                        .font(.caption2.weight(.bold))
                        .foregroundStyle(.secondary)
                } else {
                    Text("Unranked")
                        .scaledFont(10)
                        .foregroundStyle(.tertiary)
                }
            }

            if !dynamicTypeSize.isAccessibilitySize {
                loadoutGrid(participant)
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
    }

    /// Width budget matters here: two of these plus the lane marker have to
    /// fit inside ~390pt. A narrow rune/summoner column on the outer edge and
    /// a 4x2 item grid keeps each side at ~90pt so nothing overflows.
    private func loadoutGrid(_ participant: MatchParticipantSummary) -> some View {
        let trailing = alignment == .trailing
        let spells = Array(participant.summonerSpellIDs.prefix(2))
        let cell = itemCell

        return HStack(alignment: .top, spacing: 4) {
            if trailing {
                // Raw slots, not a compacted list — see itemGrid.
                itemGrid(participant.items, size: cell, trailing: true)
                broughtColumn(keystone: participant.keystoneID, spells: spells, size: cell)
            } else {
                broughtColumn(keystone: participant.keystoneID, spells: spells, size: cell)
                itemGrid(participant.items, size: cell, trailing: false)
            }
        }
    }

    /// Keystone then the two summoner spells, stacked on the outer edge.
    private func broughtColumn(keystone: Int, spells: [Int], size: CGFloat) -> some View {
        VStack(spacing: 2) {
            if keystone != 0 {
                RuneIconView(runeID: keystone, size: size)
            } else {
                emptySlot(size)
            }
            ForEach(0..<2, id: \.self) { index in
                if index < spells.count {
                    SpellIconView(spellID: spells[index], size: size)
                } else {
                    emptySlot(size)
                }
            }
        }
    }

    /// Riot's item array is seven *fixed* slots: 0-5 are the build, slot 6 is
    /// always the trinket, and an unfilled slot is 0. Compacting that array
    /// (filtering out the zeros) breaks the mapping — with only four items
    /// built, the trinket slides up into the build grid and the trinket row
    /// disappears entirely. So slots are read by index and the trinket keeps
    /// its own fixed cell, which is safe precisely because every player has one.
    private func itemGrid(_ items: [Int], size: CGFloat, trailing: Bool) -> some View {
        let build = (0..<6).map { $0 < items.count ? items[$0] : 0 }
        let trinket = items.count > 6 ? items[6] : 0
        let ordered = trailing ? Array(build.reversed()) : build

        return VStack(alignment: trailing ? .trailing : .leading, spacing: 2) {
            itemRow(Array(ordered.prefix(3)), size: size)
            itemRow(Array(ordered.dropFirst(3)), size: size)
            // Always drawn, so the trinket sits in the same place on every row
            // regardless of how much of the build got finished.
            itemSlot(trinket, size: size)
                .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        }
        // Reserve the build grid's width so the trinket line can't shrink the
        // column and knock the two sides out of alignment.
        .frame(width: size * 3 + 4, alignment: trailing ? .trailing : .leading)
    }

    private func itemRow(_ items: [Int], size: CGFloat) -> some View {
        HStack(spacing: 2) {
            ForEach(Array(items.prefix(3).enumerated()), id: \.offset) { _, item in
                itemSlot(item, size: size)
            }
        }
    }

    @ViewBuilder
    private func itemSlot(_ itemID: Int, size: CGFloat) -> some View {
        if itemID != 0 {
            // Display-only: at 16pt this can't reach a usable hit area, and a
            // mis-tap would open a sheet about the wrong item. Inspection lives
            // in the expanded Items panel instead.
            ItemIconView(itemID: itemID, size: size, interactive: false)
        } else {
            emptySlot(size)
        }
    }

    /// Invisible rather than a grey well: an unfilled slot is not information,
    /// and drawing it made half-built rows look like broken placeholders. The
    /// space is still reserved so the grid stays aligned across both sides.
    private func emptySlot(_ size: CGFloat) -> some View {
        Color.clear.frame(width: size, height: size)
    }

    private func awardBadge(_ award: MatchAward) -> some View {
        Text(award.text)
            .scaledFont(8, weight: .black)
            .foregroundStyle(.white)
            .padding(.horizontal, 4)
            .padding(.vertical, 1.5)
            .background(award.tint)
            .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
    }

}
