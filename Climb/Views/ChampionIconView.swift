import SwiftUI

struct ChampionIconView: View {
    let championName: String
    var size: CGFloat = 40

    @State private var iconURL: URL?

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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
        .task(id: championName) {
            iconURL = await DataDragonService.shared.championIconURL(for: championName)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.22)
            .fill(.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
    }
}
