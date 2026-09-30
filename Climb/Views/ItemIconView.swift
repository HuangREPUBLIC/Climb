import SwiftUI

struct ItemIconView: View {
    let itemID: Int
    var size: CGFloat = 32
    var interactive: Bool = true

    @State private var showingDetail = false

    var body: some View {
        RemoteIcon(id: itemID, url: { await DataDragonService.shared.itemIconURL(for: itemID) }) {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(.secondary.opacity(0.12))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.2)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        // An interactive icon smaller than the 44pt minimum has its hit area
        // padded out to it; the icon itself is untouched. Non-interactive icons
        // get no extra frame, so dense grids stay dense.
        .frame(
            minWidth: interactive ? 44 : nil,
            minHeight: interactive ? 44 : nil
        )
        .contentShape(Rectangle())
        .onTapGesture {
            guard interactive else { return }
            showingDetail = true
        }
        .itemPopover(itemID, isPresented: $showingDetail)
    }
}
