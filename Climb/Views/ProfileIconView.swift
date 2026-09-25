import SwiftUI

struct ProfileIconView: View {
    let profileIconID: Int
    var size: CGFloat = 32

    var body: some View {
        RemoteIcon(id: profileIconID, url: { await DataDragonService.shared.profileIconURL(for: profileIconID) }) {
            Circle()
                .fill(.secondary.opacity(0.2))
                .overlay {
                    Image(systemName: "person.fill")
                        .foregroundStyle(.secondary)
                }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }
}
