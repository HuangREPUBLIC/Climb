import SwiftUI

struct ParticipantRowView: View {
    let participant: MatchParticipantSummary

    @ScaledMetric(relativeTo: .caption2) private var itemSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var portraitSize: CGFloat = 26

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                ChampionIconView(championName: participant.champion, size: portraitSize)

                Text(participant.isLinkedPlayer ? "\(participant.riotIdGameName) (You)" : participant.riotIdGameName)
                    .font(.caption)
                    .fontWeight(participant.isLinkedPlayer ? .bold : .regular)
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .frame(minWidth: 0, maxWidth: .infinity, alignment: .leading)

                Text("\(participant.kills)/\(participant.deaths)/\(participant.assists)")
                    .font(.caption2.monospacedDigit())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .fixedSize()
            }

            let ownedItems = participant.items.filter { $0 != 0 }
            if !ownedItems.isEmpty {
                HStack(spacing: 2) {
                    ForEach(ownedItems, id: \.self) { item in
                        // Display-only at this size — see ItemBuildListView.
                        ItemIconView(itemID: item, size: itemSize, interactive: false)
                    }
                }
                .padding(.leading, 32)
            }
        }
        .padding(.vertical, 2)
    }
}
