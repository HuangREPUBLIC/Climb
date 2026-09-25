import SwiftUI

struct SpellIconView: View {
    let spellID: Int
    var size: CGFloat = 24

    var body: some View {
        RemoteIcon(id: spellID, url: { await DataDragonService.shared.summonerSpellIconURL(for: spellID) }) {
            RoundedRectangle(cornerRadius: size * 0.2)
                .fill(.secondary.opacity(0.12))
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.2))
    }
}
