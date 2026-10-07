import SwiftUI

/// A ranked tier's emblem. The ten emblems ship in the asset catalog as
/// `emblem-<tier>`, cropped to the badge: CommunityDragon, which used to
/// serve them, often takes ~20s or times out (Cloudflare 522).
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
                placeholder
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
        .overlay {
            Circle().strokeBorder(.white.opacity(0.5), lineWidth: 1)
        }
        .shadow(color: .black.opacity(0.25), radius: 2, y: 1)
    }

    private var placeholder: some View {
        Image(systemName: "shield.fill")
            .resizable()
            .scaledToFit()
            .foregroundStyle(.secondary.opacity(0.3))
            .frame(width: size, height: size)
    }
}
