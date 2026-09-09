import SwiftUI

/// One player's build as a named list rather than a grid of thumbnails.
///
/// The scoreboard row shows items as a 16pt grid, which is the right density
/// for scanning ten players but far below the 44pt minimum for anything
/// tappable — and at that size a player can't tell which of seven near-identical
/// thumbnails they are aiming at anyway. Widening those cells isn't possible
/// (four columns a side at 44pt needs more width than the phone has), so the
/// grid is display-only and inspection happens here, where a row is full width
/// and carries the item's actual name.
struct ItemBuildListView: View {
    let items: [Int]
    let alignment: HorizontalAlignment

    @State private var names: [Int: String] = [:]
    @State private var selectedItemID: Int?

    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 26

    /// Riot's array is seven fixed slots with 0 for empty; here the order is
    /// all that matters, so the empties simply drop out.
    private var owned: [Int] { items.filter { $0 != 0 } }

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            if owned.isEmpty {
                Text("No items")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                ForEach(Array(owned.enumerated()), id: \.offset) { _, item in
                    row(item)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: alignment == .leading ? .leading : .trailing)
        .task(id: owned) {
            await loadNames()
        }
        .sheet(item: $selectedItemID) { itemID in
            ItemDetailView(itemID: itemID)
        }
    }

    private func row(_ itemID: Int) -> some View {
        let trailing = alignment == .trailing
        let icon = ItemIconView(itemID: itemID, size: iconSize, interactive: false)
        let name = Text(names[itemID] ?? "…")
            .font(.caption)
            .foregroundStyle(.primary)
            .lineLimit(2)
            .multilineTextAlignment(trailing ? .trailing : .leading)
            .frame(maxWidth: .infinity, alignment: trailing ? .trailing : .leading)

        return Button {
            selectedItemID = itemID
        } label: {
            HStack(spacing: 8) {
                if !trailing { icon }
                name
                if trailing { icon }
            }
            // The 44pt floor is the whole reason this panel exists.
            .frame(minHeight: 44)
            .contentShape(Rectangle())
        }
        .buttonStyle(PressableButtonStyle())
        .accessibilityLabel(names[itemID] ?? "Item")
        .accessibilityHint("Shows this item's cost and effect")
    }

    /// Names arrive from Data Dragon's cached item table; a miss just leaves the
    /// placeholder rather than blocking the row.
    private func loadNames() async {
        var found: [Int: String] = [:]
        for id in owned {
            if let info = await DataDragonService.shared.itemInfo(for: id) {
                found[id] = info.name
            }
        }
        names = found
    }
}
