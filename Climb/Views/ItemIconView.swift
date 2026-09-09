import SwiftUI

struct ItemIconView: View {
    let itemID: Int
    var size: CGFloat = 32
    var interactive: Bool = true

    @State private var iconURL: URL?
    @State private var showingDetail = false

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFill()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .overlay {
            if iconURL != nil {
                RoundedRectangle(cornerRadius: size * 0.2)
                    .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
            }
        }
        .task(id: itemID) {
            iconURL = await DataDragonService.shared.itemIconURL(for: itemID)
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
        .sheet(isPresented: $showingDetail) {
            ItemDetailView(itemID: itemID)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.2)
            .fill(.secondary.opacity(0.12))
    }
}
