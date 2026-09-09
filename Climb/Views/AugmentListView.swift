import SwiftUI

/// The augment picks for one player in Arena / Brawl / ARAM: Mayhem, shown as
/// icon + name + effect the way the reference app lists them.
struct AugmentListView: View {
    let ids: [Int]
    let alignment: HorizontalAlignment

    @State private var augments: [AugmentService.Augment] = []
    @State private var selectedAugment: AugmentService.Augment?
    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 24

    var body: some View {
        VStack(alignment: alignment, spacing: 8) {
            if augments.isEmpty {
                if ids.isEmpty {
                    Text("No augments")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                } else {
                    // IDs exist but the table hasn't loaded yet — show the
                    // slots rather than an empty panel.
                    HStack(spacing: 4) {
                        ForEach(ids, id: \.self) { _ in
                            Circle().fill(.secondary.opacity(0.15)).frame(width: iconSize, height: iconSize)
                        }
                    }
                }
            } else {
                ForEach(augments) { augment in
                    row(augment)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .task(id: ids) {
            augments = await AugmentService.shared.augments(ids: ids)
        }
        .sheet(item: $selectedAugment) { augment in
            AugmentDetailSheet(augment: augment)
        }
    }

    private func row(_ augment: AugmentService.Augment) -> some View {
        Button {
            selectedAugment = augment
        } label: {
            HStack(alignment: .top, spacing: 6) {
                AsyncImage(url: augment.iconURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        Circle().fill(.secondary.opacity(0.15))
                    }
                }
                .frame(width: iconSize, height: iconSize)

                VStack(alignment: .leading, spacing: 1) {
                    Text(augment.name)
                        .font(.caption.weight(.semibold))
                        .lineLimit(2)
                    if !augment.description.isEmpty {
                        Text(augment.description)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .lineLimit(2)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
    }
}

/// Full name and effect for a tapped augment.
struct AugmentDetailSheet: View {
    let augment: AugmentService.Augment
    @Environment(\.dismiss) private var dismiss
    @ScaledMetric(relativeTo: .title3) private var iconSize: CGFloat = 56

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    HStack(spacing: 12) {
                        AsyncImage(url: augment.iconURL) { phase in
                            if let image = phase.image {
                                image.resizable().scaledToFit()
                            } else {
                                Circle().fill(.secondary.opacity(0.15))
                            }
                        }
                        .frame(width: iconSize, height: iconSize)

                        Text(augment.name).font(.title3.bold())
                    }

                    if !augment.description.isEmpty {
                        Text(augment.description)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding()
            }
            .navigationTitle("Augment")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// The player's full rune page for standard modes — every primary-tree pick
/// (keystone first, shown larger) and both secondary picks, grouped under
/// their tree icons. Summoner spells are deliberately absent: they aren't
/// runes, and they already appear on the scoreboard row itself.
struct RuneListView: View {
    let primaryRuneIDs: [Int]
    let secondaryRuneIDs: [Int]
    let primaryStyleID: Int
    let subStyleID: Int
    let statPerkIDs: [Int]
    let alignment: HorizontalAlignment

    /// Sizes scale with the user's text size so the page doesn't stay tiny
    /// (or overflow) at accessibility sizes.
    @ScaledMetric(relativeTo: .caption) private var keystoneSize: CGFloat = 30
    @ScaledMetric(relativeTo: .caption) private var runeSize: CGFloat = 22
    @ScaledMetric(relativeTo: .caption2) private var treeSize: CGFloat = 16
    /// Smaller than a rune — shards are a minor pick, and the client draws
    /// them smaller too.
    @ScaledMetric(relativeTo: .caption2) private var shardSize: CGFloat = 18

    @State private var selectedRuneID: Int?

    private var hasRunes: Bool { !primaryRuneIDs.isEmpty || !secondaryRuneIDs.isEmpty }

    var body: some View {
        VStack(alignment: alignment, spacing: 10) {
            if hasRunes {
                treeGroup(styleID: primaryStyleID, runeIDs: primaryRuneIDs, isPrimary: true)
                if !secondaryRuneIDs.isEmpty {
                    treeGroup(styleID: subStyleID, runeIDs: secondaryRuneIDs, isPrimary: false)
                }
                if !statPerkIDs.isEmpty {
                    shardGroup
                }
            } else {
                Text("No rune data")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .sheet(item: $selectedRuneID) { runeID in
            RuneDetailSheet(runeID: runeID)
        }
    }

    /// Shards get their own group rather than riding along with the secondary
    /// tree: Riot picks them from a separate table (`perks.statPerks`), and the
    /// client shows them in their own column as well.
    private var shardGroup: some View {
        VStack(alignment: alignment, spacing: 5) {
            Text("Shards")
                .font(.caption2)
                .foregroundStyle(.secondary)

            FlowLayout(spacing: 4) {
                ForEach(Array(statPerkIDs.enumerated()), id: \.offset) { _, shard in
                    Button {
                        selectedRuneID = shard
                    } label: {
                        // Data Dragon's shard art is a bare glyph on transparency,
                        // unlike rune icons which carry their own disc — without
                        // a backing they float loose next to the rows above.
                        RuneIconView(runeID: shard, size: shardSize)
                            .padding(4)
                            .background(Color.secondary.opacity(0.15), in: Circle())
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }

    private func treeGroup(styleID: Int, runeIDs: [Int], isPrimary: Bool) -> some View {
        VStack(alignment: alignment, spacing: 5) {
            HStack(spacing: 4) {
                if styleID != 0 {
                    RuneIconView(runeID: styleID, size: treeSize)
                }
                Text(isPrimary ? "Primary" : "Secondary")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            // Wraps rather than overflowing when icons scale up.
            FlowLayout(spacing: 4) {
                ForEach(Array(runeIDs.enumerated()), id: \.offset) { index, rune in
                    Button {
                        selectedRuneID = rune
                    } label: {
                        RuneIconView(runeID: rune, size: isPrimary && index == 0 ? keystoneSize : runeSize)
                    }
                    .buttonStyle(PressableButtonStyle())
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
    }
}

/// `Int` isn't Identifiable, so this lets a rune id drive `.sheet(item:)`.
extension Int: @retroactive Identifiable {
    public var id: Int { self }
}

/// Name and effect for a tapped rune, resolved from Data Dragon.
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

/// Minimal wrapping row: lays children left to right and starts a new line
/// when the next would overflow. Keeps rune rows intact at large text sizes
/// instead of letting them run off the edge.
struct FlowLayout: Layout {
    var spacing: CGFloat = 4

    /// One row's worth of items plus the tallest height in it, so placement
    /// can centre each item vertically. Without this the keystone (which is
    /// larger than the other runes) top-aligns against them and the row looks
    /// misaligned.
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
        // Report the content's own width, not the whole proposal, so a
        // centred parent can still centre the rows.
        return CGSize(width: min(widest, maxWidth), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in rows(maxWidth: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for entry in row.sizes {
                // Centre within the row so mixed icon sizes share a midline.
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
