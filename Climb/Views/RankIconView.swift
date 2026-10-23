import SwiftUI

/// A ranked tier's emblem, bundled as `emblem-<tier>` because CommunityDragon often takes ~20s or times out.
struct RankIconView: View {
    let tier: String
    var size: CGFloat = 48

    var body: some View {
        Group {
            if let image = UIImage(named: "emblem-\(tier.lowercased())") {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
            } else {
                Image(systemName: "shield.fill")
                    .resizable()
                    .scaledToFit()
                    .foregroundStyle(.secondary.opacity(0.3))
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }
}
