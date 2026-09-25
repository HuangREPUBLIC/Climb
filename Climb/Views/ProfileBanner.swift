import SwiftUI

/// The splash-art banner at the top of a profile — yours or another player's.
///
/// The backdrop is splash art of whoever the player uses most. A flat accent
/// gradient said nothing about the person it belonged to, and the glass rank
/// chip needs something behind it to refract. Everything sits inside the
/// banner rather than straddling its edge, which read as cramped.
struct ProfileBanner<Content: View>: View {
    let profileIconID: Int?
    let level: Int?
    let bannerChampion: String?
    /// Name, rank and anything else under the portrait.
    @ViewBuilder let content: () -> Content

    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 80

    var body: some View {
        VStack(spacing: 12) {
            avatar
            content()
        }
        .padding(.horizontal, 16)
        .frame(maxWidth: .infinity)
        .padding(.top, 12)
        .padding(.bottom, 24)
        .background { backdrop }
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: 28, bottomTrailingRadius: 28))
    }

    private var backdrop: some View {
        ZStack {
            if let bannerChampion, let url = DataDragonService.shared.splashArtURL(for: bannerChampion) {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        accentFallback
                    }
                }
            } else {
                accentFallback
            }

            // Splash art puts the champion off to one side and can be bright
            // anywhere, so the scrim carries the text contrast on its own.
            LinearGradient(
                stops: [
                    .init(color: .black.opacity(0.55), location: 0),
                    .init(color: .black.opacity(0.28), location: 0.45),
                    .init(color: .black.opacity(0.70), location: 1)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        }
    }

    /// Before any match is loaded, and whenever the art fails — the banner
    /// should never collapse to a blank rectangle.
    private var accentFallback: some View {
        LinearGradient(
            colors: [Theme.accent, Theme.accent.opacity(0.72)],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
        )
    }

    private var avatar: some View {
        Group {
            if let profileIconID {
                ProfileIconView(profileIconID: profileIconID, size: avatarSize)
            } else {
                Circle()
                    .fill(.white.opacity(0.25))
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.largeTitle)
                            .foregroundStyle(.white)
                    }
            }
        }
        .overlay(Circle().strokeBorder(.white.opacity(0.9), lineWidth: 3))
        // Level rides on the portrait the way the game client draws it.
        .overlay(alignment: .bottom) {
            if let level {
                Text("\(level)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(.black.opacity(0.6), in: Capsule())
                    .overlay(Capsule().strokeBorder(.white.opacity(0.5), lineWidth: 1))
                    .offset(y: 7)
            }
        }
        .shadow(color: .black.opacity(0.35), radius: 12, y: 4)
    }
}

/// A Riot ID styled for the banner.
struct BannerTitle: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.title2.bold())
            .foregroundStyle(.white)
            .multilineTextAlignment(.center)
            .lineLimit(2)
            .minimumScaleFactor(0.5)
            .frame(maxWidth: .infinity)
            .shadow(color: .black.opacity(0.45), radius: 6, y: 1)
    }
}

/// Solo-queue rank on Liquid Glass, which picks up the art behind it instead
/// of flattening a white rectangle over it.
struct RankChip: View {
    let tier: String?
    let division: String?
    let leaguePoints: Int?

    @ScaledMetric(relativeTo: .caption) private var iconSize: CGFloat = 26

    var body: some View {
        HStack(spacing: 6) {
            if let tier, let division {
                RankIconView(tier: tier, size: iconSize)
                Text(RankEmblemService.displayName(tier: tier, division: division))
                    .font(.caption.weight(.bold))
                    .foregroundStyle(.white)
                if let leaguePoints {
                    Text("\u{00B7} \(leaguePoints) LP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.white.opacity(0.85))
                }
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.85))
                Text("Unranked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.white)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .glassEffect()
    }
}

/// Three headline numbers under a profile banner.
///
/// The columns become rows at accessibility sizes: a third of the width can't
/// hold "Win rate" and its number without truncating.
struct StatSummaryCard: View {
    struct Stat {
        let icon: String
        /// Only colour-code a number whose colour carries meaning.
        var tint: Color = .secondary
        let label: String
        let value: String
    }

    let stats: [Stat]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var dividerHeight: CGFloat = 40

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(spacing: 12) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                        if index > 0 { Divider() }
                        column(stat)
                    }
                }
            } else {
                HStack(spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                        if index > 0 { Divider().frame(height: dividerHeight) }
                        column(stat)
                    }
                }
            }
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
        .cardShadow()
    }

    private func column(_ stat: Stat) -> some View {
        VStack(spacing: 6) {
            Image(systemName: stat.icon)
                .font(.caption)
                .foregroundStyle(stat.tint)
            Text(stat.value).font(.title3.bold()).monospacedDigit()
            Text(stat.label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}
