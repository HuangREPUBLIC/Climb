import SwiftUI

/// The "Matchup" tab (对位): pick an opponent, compare your game against
/// theirs, and see the genuine head-to-head kill record between you —
/// the latter reconstructed from match timeline events at import time.
struct PlayerMatchupView: View {
    let match: Match
    let region: RiotRegion?

    /// Either side can be any of the ten players — comparing two teammates or
    /// two enemies is just as valid as "me vs my laner".
    @State private var leftID: String?
    @State private var rightID: String?

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    @ScaledMetric(relativeTo: .caption) private var radarHeight: CGFloat = 240
    @ScaledMetric(relativeTo: .caption2) private var teamStripHeight: CGFloat = 34
    @ScaledMetric(relativeTo: .caption) private var pickerChipSize: CGFloat = 38
    @ScaledMetric(relativeTo: .caption2) private var pickerBadgeSize: CGFloat = 13
    @ScaledMetric(relativeTo: .subheadline) private var combatantPortraitSize: CGFloat = 44
    @ScaledMetric(relativeTo: .caption) private var rowPortraitSize: CGFloat = 28
    @ScaledMetric(relativeTo: .caption) private var statCellMinWidth: CGFloat = 130
    @ScaledMetric(relativeTo: .subheadline) private var killedColumnWidth: CGFloat = 52
    @ScaledMetric(relativeTo: .subheadline) private var diedColumnWidth: CGFloat = 56
    @ScaledMetric(relativeTo: .subheadline) private var assistedColumnWidth: CGFloat = 62

    private var linkedPlayer: MatchParticipantSummary? {
        match.focusParticipant
    }
    private var linkedTeamId: Int { linkedPlayer?.teamId ?? 100 }
    private var allies: [MatchParticipantSummary] {
        match.participants.filter { $0.teamId == linkedTeamId }
    }
    private var opponents: [MatchParticipantSummary] {
        match.participants.filter { $0.teamId != linkedTeamId }
    }
    private var orderedParticipants: [MatchParticipantSummary] { allies + opponents }

    private var leftPlayer: MatchParticipantSummary? {
        match.participants.first { $0.puuid == leftID } ?? linkedPlayer ?? allies.first
    }
    private var rightPlayer: MatchParticipantSummary? {
        match.participants.first { $0.puuid == rightID } ?? defaultOpponent
    }
    /// Default the right side to the lane opponent when there is one.
    private var defaultOpponent: MatchParticipantSummary? {
        let myRole = linkedPlayer?.role ?? ""
        return opponents.first { $0.role == myRole && !myRole.isEmpty } ?? opponents.first
    }
    private var hasHeadToHeadData: Bool { !match.opponentEncounters.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let leftPlayer, let rightPlayer {
                comparisonCard(me: leftPlayer, opponent: rightPlayer)
            }
            headToHeadCard
        }
        .onAppear {
            if leftID == nil { leftID = linkedPlayer?.puuid ?? allies.first?.puuid }
            if rightID == nil { rightID = defaultOpponent?.puuid }
        }
    }

    private func encounter(for opponent: MatchParticipantSummary) -> OpponentEncounter? {
        match.opponentEncounters.first { $0.opponentPuuid == opponent.puuid }
    }

    // MARK: - Comparison card (picker + versus banner + radar)

    private func comparisonCard(me: MatchParticipantSummary, opponent: MatchParticipantSummary) -> some View {
        let axes = radarAxes(me: me, opponent: opponent)
        return VStack(spacing: 0) {
            opponentPicker
            versusBanner(me: me, opponent: opponent)

            VStack(spacing: 14) {
                RadarChartView(
                    axes: axes.map { RadarChartView.Axis(label: $0.label, primaryValue: $0.meValue, secondaryValue: $0.opponentValue) },
                    primaryColor: .blue,
                    secondaryColor: .red
                )
                .frame(height: radarHeight)

                let statColumns = dynamicTypeSize.isAccessibilitySize
                    ? [GridItem(.adaptive(minimum: statCellMinWidth), spacing: 8)]
                    : [GridItem(.flexible()), GridItem(.flexible())]
                LazyVGrid(columns: statColumns, spacing: 8) {
                    ForEach(axes) { axis in
                        statComparisonRow(axis: axis)
                    }
                }
            }
            .padding(16)
        }
        .cardSurface(padding: 0)
    }

    /// One row per team rather than two rows of all ten: every player still
    /// appears exactly once, each side is picked from its own row, and the
    /// swap button covers "compare two allies" without duplicating portraits.
    private var opponentPicker: some View {
        VStack(spacing: 6) {
            teamRow(players: allies, tint: .blue)
            teamRow(players: opponents, tint: .red)
        }
        .padding(.horizontal, 12)
        .padding(.top, 12)
        .padding(.bottom, 4)
    }

    private func teamRow(players: [MatchParticipantSummary], tint: Color) -> some View {
        HStack(spacing: 6) {
            Rectangle()
                .fill(tint)
                .frame(width: 3, height: teamStripHeight)
                .clipShape(Capsule())

            ForEach(players, id: \.puuid) { player in
                pickerChip(player, tint: tint)
            }
        }
    }

    private func pickerChip(_ participant: MatchParticipantSummary, tint: Color) -> some View {
        let isLeft = participant.puuid == leftPlayer?.puuid
        let isRight = participant.puuid == rightPlayer?.puuid
        let isSelected = isLeft || isRight

        return Button {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.85)) {
                select(participant)
            }
        } label: {
            ChampionIconView(championName: participant.champion, size: pickerChipSize)
                .overlay {
                    RoundedRectangle(cornerRadius: pickerChipSize * 0.22)
                        .strokeBorder(isSelected ? tint : .clear, lineWidth: 2.5)
                }
                .overlay(alignment: .topTrailing) {
                    if isSelected {
                        Text(isLeft ? "A" : "B")
                            .scaledFont(8, weight: .black)
                            .foregroundStyle(.white)
                            .frame(width: pickerBadgeSize, height: pickerBadgeSize)
                            .background(Circle().fill(tint))
                            .offset(x: 3, y: -3)
                    }
                }
                .opacity(isSelected ? 1 : 0.5)
                .scaleEffect(isSelected ? 1.05 : 1)
        }
        .buttonStyle(PressableButtonStyle())
        .frame(maxWidth: .infinity)
        .accessibilityLabel(participant.riotIdGameName)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// Tapping a player assigns them to the side their team occupies; tapping
    /// one that's already selected swaps the two sides.
    private func select(_ participant: MatchParticipantSummary) {
        if participant.puuid == leftPlayer?.puuid || participant.puuid == rightPlayer?.puuid {
            let previousLeft = leftID
            leftID = rightID
            rightID = previousLeft
            return
        }
        if participant.teamId == linkedTeamId {
            leftID = participant.puuid
        } else {
            rightID = participant.puuid
        }
    }

    private func versusBanner(me: MatchParticipantSummary, opponent: MatchParticipantSummary) -> some View {
        let separator = Text("VS")
            .font(.caption2.weight(.black))
            .foregroundStyle(.secondary)

        // Portrait + name + KDA twice across one row stops fitting well before
        // the largest sizes, so the two sides stack there.
        return Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 8) {
                    combatant(me, tint: .blue, alignment: .leading)
                    separator
                    combatant(opponent, tint: .red, alignment: .leading)
                }
            } else {
                HStack(spacing: 0) {
                    combatant(me, tint: .blue, alignment: .leading)
                    separator.padding(.horizontal, 10)
                    combatant(opponent, tint: .red, alignment: .trailing)
                }
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(
            LinearGradient(
                colors: [.blue.opacity(0.14), .clear, .red.opacity(0.14)],
                startPoint: .leading,
                endPoint: .trailing
            )
        )
    }

    private func combatant(_ participant: MatchParticipantSummary, tint: Color, alignment: HorizontalAlignment) -> some View {
        let trailing = alignment == .trailing
        return HStack(spacing: 10) {
            if !trailing {
                ChampionIconView(championName: participant.champion, size: combatantPortraitSize)
            }
            VStack(alignment: alignment, spacing: 2) {
                Text(participant.isLinkedPlayer ? "You" : participant.riotIdGameName)
                    .font(.subheadline.weight(.bold))
                    .foregroundStyle(tint)
                    .lineLimit(1)
                    .minimumScaleFactor(0.7)
                Text("\(participant.kills)/\(participant.deaths)/\(participant.assists)")
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            if trailing {
                ChampionIconView(championName: participant.champion, size: combatantPortraitSize)
            }
        }
        .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)
        .accessibilityElement(children: .combine)
    }

    // MARK: - Radar data

    private struct RadarAxis: Identifiable {
        let id = UUID()
        let label: String
        let meValue: Double
        let opponentValue: Double
        let meDisplay: String
        let opponentDisplay: String
    }

    private func radarAxes(me: MatchParticipantSummary, opponent: MatchParticipantSummary) -> [RadarAxis] {
        [
            RadarAxis(label: "Participation", meValue: participation(me), opponentValue: participation(opponent),
                      meDisplay: "\(Int(participation(me).rounded()))%", opponentDisplay: "\(Int(participation(opponent).rounded()))%"),
            RadarAxis(label: "Gold", meValue: Double(me.goldEarned), opponentValue: Double(opponent.goldEarned),
                      meDisplay: me.goldEarned.formatted(), opponentDisplay: opponent.goldEarned.formatted()),
            RadarAxis(label: "KDA", meValue: me.kda, opponentValue: opponent.kda,
                      meDisplay: String(format: "%.1f", me.kda), opponentDisplay: String(format: "%.1f", opponent.kda)),
            RadarAxis(label: "Damage taken", meValue: Double(me.damageTaken), opponentValue: Double(opponent.damageTaken),
                      meDisplay: me.damageTaken.formatted(), opponentDisplay: opponent.damageTaken.formatted()),
            RadarAxis(label: "Healing", meValue: Double(me.totalHeal), opponentValue: Double(opponent.totalHeal),
                      meDisplay: me.totalHeal.formatted(), opponentDisplay: opponent.totalHeal.formatted()),
            RadarAxis(label: "Damage", meValue: Double(me.damageDealtToChampions), opponentValue: Double(opponent.damageDealtToChampions),
                      meDisplay: me.damageDealtToChampions.formatted(), opponentDisplay: opponent.damageDealtToChampions.formatted())
        ]
    }

    private func statComparisonRow(axis: RadarAxis) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(axis.label).font(.caption2).foregroundStyle(.secondary)
            HStack {
                Text(axis.meDisplay).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.blue)
                Spacer()
                Text(axis.opponentDisplay).font(.caption.weight(.semibold).monospacedDigit()).foregroundStyle(.red)
            }
        }
        .padding(8)
        .background(Theme.surfaceRaised)
        .clipShape(RoundedRectangle(cornerRadius: Theme.chipRadius, style: .continuous))
    }

    // MARK: - Head-to-head kill record

    private var headToHeadCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Label("Your head-to-head kills", systemImage: "target")
                    .font(.headline)
                Text("Who actually killed whom, from the match timeline.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if hasHeadToHeadData {
                // A four-column table: it stops being a table long before the
                // largest text size, so its scaling is capped.
                VStack(spacing: 0) {
                    headToHeadHeader
                    ForEach(Array(opponents.enumerated()), id: \.element.puuid) { index, opponent in
                        headToHeadRow(opponent)
                            .background(index.isMultiple(of: 2) ? Color.clear : Theme.surfaceRaised)
                    }
                }
                .denseRowScaling()
                .clipShape(RoundedRectangle(cornerRadius: Theme.controlRadius, style: .continuous))
            } else {
                HStack(spacing: 10) {
                    Image(systemName: "arrow.triangle.2.circlepath")
                        .foregroundStyle(.secondary)
                    Text("Re-sync this account to pull timeline data for past matches.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 8)
            }
        }
        .cardSurface()
    }

    private var headToHeadHeader: some View {
        HStack {
            Text("Opponent").font(.caption2).foregroundStyle(.secondary).frame(maxWidth: .infinity, alignment: .leading)
            Text("Killed").font(.caption2).foregroundStyle(.secondary).frame(width: killedColumnWidth, alignment: .trailing)
            Text("Died to").font(.caption2).foregroundStyle(.secondary).frame(width: diedColumnWidth, alignment: .trailing)
            Text("Assisted").font(.caption2).foregroundStyle(.secondary).frame(width: assistedColumnWidth, alignment: .trailing)
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }

    private func headToHeadRow(_ opponent: MatchParticipantSummary) -> some View {
        let record = encounter(for: opponent)
        return HStack {
            HStack(spacing: 8) {
                ChampionIconView(championName: opponent.champion, size: rowPortraitSize)
                Text(opponent.riotIdGameName).font(.caption).lineLimit(1).truncationMode(.tail)
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            countCell(record?.killsOnOpponent ?? 0, tint: .green, width: killedColumnWidth)
            countCell(record?.deathsToOpponent ?? 0, tint: .red, width: diedColumnWidth)
            countCell(record?.assistsOnOpponent ?? 0, tint: .secondary, width: assistedColumnWidth)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(opponent.riotIdGameName): killed \(record?.killsOnOpponent ?? 0), died to \(record?.deathsToOpponent ?? 0), assisted \(record?.assistsOnOpponent ?? 0)")
    }

    private func countCell(_ value: Int, tint: Color, width: CGFloat) -> some View {
        Text("\(value)")
            .font(.subheadline.weight(value > 0 ? .bold : .regular).monospacedDigit())
            .foregroundStyle(value > 0 ? tint : Color.secondary.opacity(0.5))
            .frame(width: width, alignment: .trailing)
    }

    // MARK: - Helpers

    private func participation(_ participant: MatchParticipantSummary) -> Double {
        let teamKills = match.participants.filter { $0.teamId == participant.teamId }.map(\.kills).reduce(0, +)
        guard teamKills > 0 else { return 0 }
        return Double(participant.kills + participant.assists) / Double(teamKills) * 100
    }
}
