import SwiftUI

struct SpellIconView: View {
    let spellID: Int
    var size: CGFloat = 24

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
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
        .task(id: spellID) {
            iconURL = await DataDragonService.shared.summonerSpellIconURL(for: spellID)
        }
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: size * 0.2)
            .fill(.secondary.opacity(0.12))
    }
}
