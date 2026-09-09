import SwiftUI

struct RankIconView: View {
    let tier: String
    var size: CGFloat = 48

    /// CommunityDragon's emblem PNGs pad the actual badge art inside a much
    /// larger transparent canvas (verified: the visible badge is only
    /// ~17-35% of the image's height depending on tier). `scaledToFit` faithfully
    /// preserves that dead space, so the badge reads as tiny no matter how big
    /// the frame is. Filling + zooming crops past the padding so the badge
    /// itself — not the invisible canvas around it — fills the frame.
    private let zoomFactor: CGFloat = 3.0

    var body: some View {
        Group {
            if let url = RankEmblemService.emblemURL(for: tier) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image
                            .resizable()
                            .scaledToFill()
                            .scaleEffect(zoomFactor)
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
