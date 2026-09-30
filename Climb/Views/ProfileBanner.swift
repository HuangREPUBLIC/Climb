import SwiftUI

/// The header card of a profile — yours or another player's: portrait, name
/// and rank on the left, the player's most-played champion on the right, and
/// the headline numbers along the bottom.
///
/// A card inset from the edges rather than splash art bled to the screen
/// edge: splash art is landscape, and stretched over a tall header it cropped
/// down to a stray elbow. The champion's portrait loading-screen art fits a
/// card's side whole instead, fading into the white.
struct ProfileBanner<Content: View, Footer: View>: View {
    let profileIconID: Int?
    let level: Int?
    /// The player's games; the most played champion fronts the card.
    let matches: [Match]
    /// Name, rank and anything else beside the portrait.
    @ViewBuilder let content: () -> Content
    /// The strip along the bottom, usually `StatSummaryCard(embedded: true)`.
    @ViewBuilder let footer: () -> Footer

    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 60
    @ScaledMetric(relativeTo: .title2) private var artWidth: CGFloat = 140

    private var mainChampion: (name: String, games: Int)? {
        Dictionary(grouping: matches.compactMap(\.leagueStats?.champion)) { $0 }
            .max { $0.value.count < $1.value.count }
            .map { ($0.key, $0.value.count) }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Portrait above the name rather than beside it, so the name and
            // rank get the card's width up to the art.
            HStack(alignment: .top, spacing: 0) {
                VStack(alignment: .leading, spacing: 8) {
                    avatar
                        .padding(.bottom, 8)
                    content()
                    if let mainChampion {
                        Text("MAIN · \(mainChampion.name) · \(mainChampion.games) games")
                            .scaledFont(10, weight: .bold)
                            .tracking(0.6)
                            .foregroundStyle(Theme.accent)
                            .lineLimit(1)
                            .minimumScaleFactor(0.8)
                    }
                }
                // Text stops where the art is still visible.
                Spacer(minLength: artWidth * 0.75)
            }
            .padding(16)
            .frame(maxWidth: .infinity, minHeight: 150, alignment: .leading)
            .background(alignment: .trailing) { championArt }

            footer()
        }
        .background(Theme.surface)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 24, style: .continuous).strokeBorder(Theme.accent.opacity(0.25), lineWidth: 1))
        .cardShadow()
    }

    /// Head-and-shoulders of the portrait art, melting into the card on its
    /// left and bottom edges so the text beside it stays on plain ground.
    @ViewBuilder
    private var championArt: some View {
        if let name = mainChampion?.name, let url = DataDragonService.shared.loadingArtURL(for: name) {
            Color.clear
                .frame(width: artWidth)
                .overlay(alignment: .top) {
                    // Oversized a little: loading art carries a dark frame
                    // along its edges, pushed out past the clip here.
                    AsyncImage(url: url) { $0.resizable().aspectRatio(contentMode: .fill) } placeholder: { Color.clear }
                        .padding(-10)
                }
                .clipped()
                .mask {
                    LinearGradient(colors: [.clear, .black], startPoint: .leading, endPoint: UnitPoint(x: 0.6, y: 0.5))
                        .mask(LinearGradient(colors: [.black, .black, .clear], startPoint: .top, endPoint: .bottom))
                }
                .accessibilityHidden(true)
        }
    }

    private var avatar: some View {
        Group {
            if let profileIconID {
                ProfileIconView(profileIconID: profileIconID, size: avatarSize)
            } else {
                Circle()
                    .fill(Theme.surfaceRaised)
                    .frame(width: avatarSize, height: avatarSize)
                    .overlay {
                        Image(systemName: "person.fill")
                            .font(.title)
                            .foregroundStyle(.secondary)
                    }
            }
        }
        .overlay(Circle().strokeBorder(Theme.accent, lineWidth: 2.5))
        // Level rides on the portrait the way the game client draws it.
        .overlay(alignment: .bottom) {
            if let level {
                Text("\(level)")
                    .font(.caption2.weight(.bold).monospacedDigit())
                    .foregroundStyle(.white)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(Theme.accent, in: Capsule())
                    .offset(y: 7)
            }
        }
    }
}

extension ProfileBanner where Footer == EmptyView {
    init(profileIconID: Int?, level: Int?, matches: [Match], @ViewBuilder content: @escaping () -> Content) {
        self.init(profileIconID: profileIconID, level: level, matches: matches, content: content) { EmptyView() }
    }
}

/// A Riot ID styled for the banner: the name large, the tag under it.
struct BannerTitle: View {
    let text: String

    var body: some View {
        let parts = text.split(separator: "#", maxSplits: 1)
        VStack(alignment: .leading, spacing: 0) {
            Text(parts.first.map(String.init) ?? text)
                .font(.title3.bold())
                .lineLimit(1)
                .minimumScaleFactor(0.6)
            if parts.count == 2 {
                Text("#\(parts[1])")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(.secondary)
            }
        }
    }
}

/// Solo-queue rank as a pill on the profile card.
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
                    .foregroundStyle(.primary)
                if let leaguePoints {
                    Text("\u{00B7} \(leaguePoints) LP")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            } else {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("Unranked")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(.primary)
            }
        }
        .lineLimit(1)
        .minimumScaleFactor(0.7)
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(Theme.surfaceRaised, in: Capsule())
    }
}

/// Three headline numbers, each with a plain-language line under it, since
/// "1.32 KDA" means nothing to someone who doesn't play.
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
        /// Colours the number with `tint` too, when the colour is the verdict.
        var tintsValue = false
        var caption: String?
    }

    let stats: [Stat]
    /// A bare row for the bottom of another card, instead of a card of its own.
    var embedded = false

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .title3) private var dividerHeight: CGFloat = 56

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
                HStack(alignment: .top, spacing: 0) {
                    ForEach(Array(stats.enumerated()), id: \.offset) { index, stat in
                        if index > 0 { Divider().frame(height: dividerHeight) }
                        column(stat)
                    }
                }
            }
        }
        .modifier(StatStripSurface(embedded: embedded))
    }

    private func column(_ stat: Stat) -> some View {
        VStack(spacing: 4) {
            Image(systemName: stat.icon)
                .font(.caption)
                .foregroundStyle(stat.tint)
            Text(stat.value)
                .font(.title3.bold().monospacedDigit())
                .foregroundStyle(stat.tintsValue ? stat.tint : .primary)
            Text(stat.label)
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            if let caption = stat.caption {
                Text(caption)
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// A card of its own, or a divided strip along the bottom of the banner.
private struct StatStripSurface: ViewModifier {
    let embedded: Bool

    func body(content: Content) -> some View {
        if embedded {
            content
                .padding(.vertical, 14)
                .padding(.horizontal, 8)
                .background(Theme.surfaceRaised.opacity(0.6))
                .overlay(alignment: .top) { Divider() }
        } else {
            content.cardSurface()
        }
    }
}

extension StatSummaryCard {
    /// Win rate, KDA and record for a list of games — the same three on your
    /// own profile and a searched player's. TFT's `win` is a top-4 finish.
    init(matches: [Match], embedded: Bool = false) {
        let wins = matches.filter(\.win).count
        let winRate = matches.isEmpty ? 0 : Double(wins) / Double(matches.count) * 100
        let isTFT = matches.allSatisfy { $0.leagueStats == nil }
        let kda = FriendComparisonService.aggregate(matches).kda

        self.init(stats: [
            Stat(icon: "percent", tint: winRate >= 50 ? Theme.win : Theme.loss, label: isTFT ? "Top 4 rate" : "Win rate",
                 value: "\(Int(winRate.rounded()))%", tintsValue: true,
                 caption: winRate > 50 ? "Wins more than half" : winRate < 50 ? "Wins less than half" : "Exactly half"),
            isTFT
                ? Stat(icon: "gamecontroller.fill", tint: Theme.teal, label: "Games", value: "\(matches.count)", caption: "Synced so far")
                : Stat(icon: "bolt.fill", tint: Theme.kdaColor(kda), label: "KDA ratio", value: String(format: "%.2f", kda),
                       tintsValue: true, caption: "Takedowns per death · 3+ is good"),
            Stat(icon: "trophy.fill", tint: Theme.accent, label: "Record",
                 value: "\(wins)W \(matches.count - wins)L", caption: "\(matches.count) games")
        ], embedded: embedded)
    }
}
