import SwiftUI

/// An item's name, cost and effect — the bubble shown wherever an item is
/// tapped, so inspecting one is the same everywhere in the app.
struct ItemDetailView: View {
    let itemID: Int

    @State private var info: DataDragonService.ItemInfo?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                ItemIconView(itemID: itemID, size: 44, interactive: false)
                VStack(alignment: .leading, spacing: 2) {
                    if let info {
                        Text(info.name)
                            .font(.headline)
                        Label("\(info.totalCost) gold", systemImage: "dollarsign.circle.fill")
                            .font(.subheadline.weight(.semibold).monospacedDigit())
                            .foregroundStyle(Theme.accent)
                    } else {
                        ProgressView()
                    }
                }
            }
            if let description = info?.plainDescription, !description.isEmpty {
                Text(description)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(width: 280, alignment: .leading)
        .task {
            info = await DataDragonService.shared.itemInfo(for: itemID)
        }
    }
}

extension View {
    /// `ItemDetailView` as a popover anchored to this view — a bubble on
    /// iPhone too, rather than the sheet a popover turns into by default.
    func itemPopover(_ itemID: Int, isPresented: Binding<Bool>) -> some View {
        popover(isPresented: isPresented) {
            ItemDetailView(itemID: itemID)
                .presentationCompactAdaptation(.popover)
        }
    }
}
