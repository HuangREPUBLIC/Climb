import SwiftUI

/// The player's rune page for standard modes: primary picks (keystone larger), secondary picks and shards.
/// Summoner spells are deliberately absent: they aren't runes and already appear on the scoreboard row.
struct RuneListView: View {
    let primaryRuneIDs: [Int]
    let secondaryRuneIDs: [Int]
    let primaryStyleID: Int
    let subStyleID: Int
    let statPerkIDs: [Int]

    @ScaledMetric(relativeTo: .caption) private var keystoneSize: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var runeSize: CGFloat = 22
    @ScaledMetric(relativeTo: .caption2) private var treeSize: CGFloat = 16
    /// Smaller than a rune: shards are a minor pick, and the client draws them smaller too.
    @ScaledMetric(relativeTo: .caption2) private var shardSize: CGFloat = 18

    @State private var selectedRuneID: Int?

    private var hasRunes: Bool { !primaryRuneIDs.isEmpty || !secondaryRuneIDs.isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if hasRunes {
                group("Primary", styleID: primaryStyleID, ids: primaryRuneIDs) { index, rune in
                    RuneIconView(runeID: rune, size: index == 0 ? keystoneSize : runeSize)
                }
                if !secondaryRuneIDs.isEmpty {
                    group("Secondary", styleID: subStyleID, ids: secondaryRuneIDs) { _, rune in
                        RuneIconView(runeID: rune, size: runeSize)
                    }
                }
                // Shards are their own group: Riot picks them from a separate table (`perks.statPerks`).
                if !statPerkIDs.isEmpty {
                    group("Shards", ids: statPerkIDs) { _, shard in
                        // Bare-glyph shard art needs a backing; rune icons carry their own disc.
                        RuneIconView(runeID: shard, size: shardSize)
                            .padding(4)
                            .background(Color.secondary.opacity(0.15), in: Circle())
                    }
                }
            } else {
                Text("No rune data")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .sheet(item: $selectedRuneID) { runeID in
            RuneDetailSheet(runeID: runeID)
        }
    }

    private func group<Icon: View>(
        _ title: String,
        styleID: Int = 0,
        ids: [Int],
        @ViewBuilder icon: @escaping (_ index: Int, _ id: Int) -> Icon
    ) -> some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                if styleID != 0 {
                    RuneIconView(runeID: styleID, size: treeSize)
                }
                Text(title)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            FlowLayout(spacing: 4) {
                ForEach(Array(ids.enumerated()), id: \.offset) { index, id in
                    Button {
                        selectedRuneID = id
                    } label: {
                        icon(index, id)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
    }
}

/// `Int` isn't Identifiable, so this lets a rune id drive `.sheet(item:)`.
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

struct RuneDetailSheet: View {
    let runeID: Int
    @Environment(\.dismiss) private var dismiss
    @State private var info: DataDragonService.RuneInfo?
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 56

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        RuneIconView(runeID: runeID, size: iconSize)
                        Text(info?.name ?? "Rune")
                            .font(.title3.bold())
                    }

                    if let text = info?.longDescription, !text.isEmpty {
                        Text(text)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else if info == nil {
                        ProgressView()
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Rune")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
        .task {
            info = await DataDragonService.shared.runeInfo(for: runeID)
        }
    }
}

/// Minimal wrapping row: lays children left to right, wrapping on overflow so rows survive large text sizes.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    /// One row's items and its tallest height, so mixed sizes (the larger keystone) can share a midline.
    private struct Row {
        var sizes: [(index: Int, size: CGSize)] = []
        var height: CGFloat = 0
        var width: CGFloat = 0
    }

    private func rows(maxWidth: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = []
        var current = Row()

        for (index, view) in subviews.enumerated() {
            let size = view.sizeThatFits(.unspecified)
            let needsBreak = !current.sizes.isEmpty && current.width + size.width > maxWidth
            if needsBreak {
                rows.append(current)
                current = Row()
            }
            current.sizes.append((index, size))
            current.width += size.width + spacing
            current.height = max(current.height, size.height)
        }
        if !current.sizes.isEmpty { rows.append(current) }
        return rows
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let maxWidth = proposal.width ?? .infinity
        let rows = rows(maxWidth: maxWidth, subviews: subviews)
        let height = rows.reduce(0) { $0 + $1.height } + spacing * CGFloat(max(rows.count - 1, 0))
        let widest = rows.map { max($0.width - spacing, 0) }.max() ?? 0
        // Report the content's own width, not the proposal, so a centred parent can still centre the rows.
        return CGSize(width: min(widest, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for entry in row.sizes {
                let yOffset = (row.height - entry.size.height) / 2
                subviews[entry.index].place(
                    at: CGPoint(x: x, y: y + yOffset),
                    proposal: ProposedViewSize(entry.size)
                )
                x += entry.size.width + spacing
            }
            y += row.height + spacing
        }
    }
}
