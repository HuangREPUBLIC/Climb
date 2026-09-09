import SwiftUI

struct ItemDetailView: View {
    let itemID: Int

    @Environment(\.dismiss) private var dismiss
    @State private var info: DataDragonService.ItemInfo?

    var body: some View {
        NavigationStack {
            VStack(spacing: 16) {
                ItemIconView(itemID: itemID, size: 72, interactive: false)
                    .padding(.top, 24)

                if let info {
                    Text(info.name)
                        .font(.title3.bold())
                    Text("\(info.totalCost) gold")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if !info.plainDescription.isEmpty {
                        Text(info.plainDescription)
                            .font(.body)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                    }
                } else {
                    ProgressView()
                        .padding(.top, 8)
                }

                Spacer()
            }
            .padding()
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
            .task {
                info = await DataDragonService.shared.itemInfo(for: itemID)
            }
        }
        .presentationDetents([.medium])
    }
}
