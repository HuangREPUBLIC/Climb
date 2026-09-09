import SwiftUI

struct ProfileIconView: View {
    let profileIconID: Int
    var size: CGFloat = 32

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
        .clipShape(Circle())
        .task(id: profileIconID) {
            iconURL = await DataDragonService.shared.profileIconURL(for: profileIconID)
        }
    }

    private var placeholder: some View {
        Circle()
            .fill(.secondary.opacity(0.2))
            .overlay {
                Image(systemName: "person.fill")
                    .foregroundStyle(.secondary)
            }
    }
}
