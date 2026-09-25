import SwiftUI

struct ChampionIconView: View {
    let championName: String
    var size: CGFloat = 40

    var body: some View {
        RemoteIcon(id: championName, url: { await DataDragonService.shared.championIconURL(for: championName) }) {
            RoundedRectangle(cornerRadius: size * 0.22)
                .fill(.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.22))
        .overlay {
            RoundedRectangle(cornerRadius: size * 0.22)
                .strokeBorder(Color.primary.opacity(0.08), lineWidth: 1)
        }
    }
}
