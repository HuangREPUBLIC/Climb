import SwiftUI

struct RuneIconView: View {
    let runeID: Int
    var size: CGFloat = 24

    var body: some View {
        RemoteIcon(id: runeID, contentMode: .fit, url: { await DataDragonService.shared.runeIconURL(for: runeID) }) {
            Circle().fill(.secondary.opacity(0.12))
        }
        .frame(width: size, height: size)
    }
}
