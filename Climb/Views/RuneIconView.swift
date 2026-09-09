import SwiftUI

struct RuneIconView: View {
    let runeID: Int
    var size: CGFloat = 24

    @State private var iconURL: URL?

    var body: some View {
        Group {
            if let iconURL {
                AsyncImage(url: iconURL) { phase in
                    if let image = phase.image {
                        image.resizable().scaledToFit()
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: size, height: size)
        .task(id: runeID) {
            iconURL = await DataDragonService.shared.runeIconURL(for: runeID)
        }
    }

    private var placeholder: some View {
        Circle().fill(.secondary.opacity(0.12))
    }
}
