import SwiftUI

/// The header card of a profile — yours or another player's: portrait, name
/// and rank on the left, the player's most-played champion on the right.
///
/// A card inset from the edges rather than splash art bled to the screen
/// edge: splash art is landscape, and stretched over a tall header it cropped
/// down to a stray elbow. The champion's portrait loading-screen art fits a
/// card's side whole instead, fading into the white.
struct ProfileBanner<Content: View>: View {
    let profileIconID: Int?
    let level: Int?
    /// The player's games; the most played champion fronts the card.
    let matches: [Match]
    /// Name, rank and anything else beside the portrait.
    @ViewBuilder let content: () -> Content

    @ScaledMetric(relativeTo: .title2) private var avatarSize: CGFloat = 60
    @ScaledMetric(relativeTo: .title2) private var artWidth: CGFloat = 140

    private var mainChampion: (name: String, games: Int)? {
        Dictionary(grouping: matches.compactMap(\.leagueStats?.champion)) { $0 }
            .max { $0.value.count < $1.value.count }
            .map { ($0.key, $0.value.count) }
    }

    var body: some View {
        // Portrait beside the name: stacked above it, the banner alone took
        // half the first screen and the first match started below the fold.
        HStack(alignment: .top, spacing: 0) {
            avatar
                .padding(.trailing, 14)
            VStack(alignment: .leading, spacing: 6) {
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
            Spacer(minLength: artWidth * 0.5)
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(alignment: .trailing) { championArt }
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
        .cardSurface()
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

/// The headline numbers under a profile banner: win/loss as one horizontal
/// card, then three tiles — KDA, average rating and the last ten results.
/// TFT swaps in placements. `matches` is newest first.
struct ProfileStatsSection: View {
    let matches: [Match]

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isTFT: Bool { matches.allSatisfy { $0.leagueStats == nil } }

    /// Callers show it only when there are games: an empty list already says
    /// why, and a card of zeros under it reads as broken.
    var body: some View {
        VStack(spacing: 10) {
            WinLossCard(matches: matches, isTFT: isTFT)
            // Equal-height tiles: each fills the row, and the row is only
            // as tall as its tallest tile.
            let layout = dynamicTypeSize.isAccessibilitySize
                ? AnyLayout(VStackLayout(spacing: 10))
                : AnyLayout(HStackLayout(spacing: 10))
            layout {
                if isTFT { tftTiles } else { leagueTiles }
                lastTenTile
            }
            .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var leagueTiles: some View {
        let kda = FriendComparisonService.aggregate(matches).kda
        StatTile(title: "KDA", icon: "bolt.fill", tint: Theme.kdaColor(kda),
                 caption: "\(average(\.kills)) / \(average(\.deaths)) / \(average(\.assists)) per game") {
            Text(String(format: "%.2f", kda))
                .foregroundStyle(Theme.kdaColor(kda))
        }

        let scores = matches.compactMap(PerformanceScore.compute(for:))
        let rating = scores.isEmpty ? nil : scores.reduce(0, +) / Double(scores.count)
        StatTile(title: "Rating", icon: "star.fill", tint: Theme.accent,
                 caption: "Out of 10 · lobby average \(String(format: "%.1f", PerformanceScore.lobbyAverage))") {
            Text(rating.map { String(format: "%.1f", $0) } ?? "—")
                .foregroundStyle(rating.map(PerformanceScore.color(for:)) ?? .secondary)
        }
    }

    /// One decimal, per League game.
    private func average(_ key: KeyPath<LeagueStats, Int>) -> String {
        let lines = matches.compactMap(\.leagueStats)
        return String(format: "%.1f", Double(lines.map { $0[keyPath: key] }.reduce(0, +)) / Double(max(lines.count, 1)))
    }

    @ViewBuilder
    private var tftTiles: some View {
        let placements = matches.compactMap(\.tftStats?.placement)
        let average = placements.isEmpty ? nil : Double(placements.reduce(0, +)) / Double(placements.count)
        StatTile(title: "Avg place", icon: "list.number", tint: Theme.teal, caption: "1st is best, out of 8") {
            Text(average.map { String(format: "#%.1f", $0) } ?? "—")
                .foregroundStyle(average.map { $0 <= 4 ? Theme.win : Theme.loss } ?? .secondary)
        }
        StatTile(title: "Wins", icon: "crown.fill", tint: Theme.fair, caption: "Games finished 1st") {
            Text("\(placements.filter { $0 == 1 }.count)")
        }
    }

    private var lastTen: [Match] { Array(matches.prefix(10).reversed()) }

    private var lastTenTile: some View {
        let recent = lastTen
        let wins = recent.filter(\.win).count
        return StatTile(title: "Last \(recent.count)", icon: "clock.arrow.circlepath", tint: Theme.teal,
                        caption: "\(wins)W \(recent.count - wins)L · newest on the right") {
            ResultStrip(matches: recent, maxBarWidth: 10)
                .frame(height: 26)
        }
    }
}

/// Your own Matches tab's one-line summary. The full breakdown is the Stats
/// tab's job; repeating it here pushed the first match below the fold.
/// `matches` is newest first.
struct ProfileSummaryStrip: View {
    let matches: [Match]

    var body: some View {
        let wins = matches.filter(\.win).count
        let percent = Int((Double(wins) / Double(max(matches.count, 1)) * 100).rounded())
        let kda = FriendComparisonService.aggregate(matches).kda
        let recent = Array(matches.prefix(10).reversed())
        HStack(spacing: 16) {
            // Coloured on the printed figure, so "50%" is never red.
            figure("\(percent)%", "Win rate · \(wins)W \(matches.count - wins)L",
                   tint: percent >= 50 ? Theme.win : Theme.loss)
            if matches.contains(where: { $0.leagueStats != nil }) {
                figure(String(format: "%.2f", kda), "KDA", tint: Theme.kdaColor(kda))
            }
            VStack(alignment: .trailing, spacing: 4) {
                ResultStrip(matches: recent, maxBarWidth: 10)
                    .frame(height: 18)
                Text("Last \(recent.count) · newest right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .frame(maxWidth: .infinity, alignment: .trailing)
        }
        .cardSurface(padding: 12)
        .accessibilityElement(children: .combine)
    }

    private func figure(_ value: String, _ caption: String, tint: Color) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(value)
                .font(.title3.weight(.bold).monospacedDigit())
                .foregroundStyle(tint)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.secondary)
        }
        .fixedSize()
    }
}

/// Win rate as a number and as a bar split between wins and losses.
private struct WinLossCard: View {
    let matches: [Match]
    let isTFT: Bool

    var body: some View {
        let wins = matches.filter(\.win).count
        let losses = matches.count - wins
        let rate = Double(wins) / Double(max(matches.count, 1))
        let percent = Int((rate * 100).rounded())

        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(percent)%")
                        .font(.largeTitle.weight(.heavy).monospacedDigit())
                        .foregroundStyle(percent >= 50 ? Theme.win : Theme.loss)
                    Text(isTFT ? "Top 4 rate" : "Win rate")
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
                VStack(alignment: .trailing, spacing: 2) {
                    HStack(spacing: 12) {
                        Text("\(wins) \(isTFT ? "Top 4" : "W")").foregroundStyle(Theme.win)
                        Text("\(losses) \(isTFT ? "Bot 4" : "L")").foregroundStyle(Theme.loss)
                    }
                    .font(.title3.bold().monospacedDigit())
                    Text("\(matches.count) game\(matches.count == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            GeometryReader { geo in
                // No gap when one side is empty, or it shows as a sliver.
                let gap: CGFloat = wins == 0 || losses == 0 ? 0 : 3
                HStack(spacing: gap) {
                    Capsule().fill(Theme.win.gradient)
                        .frame(width: max((geo.size.width - gap) * rate, 0))
                    Capsule().fill(Theme.loss.gradient)
                }
            }
            .frame(height: 10)
        }
        .cardSurface()
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(isTFT ? "Top 4 rate" : "Win rate") \(percent) percent: \(wins) \(isTFT ? "top 4" : "wins"), \(losses) \(isTFT ? "bottom 4" : "losses"), \(matches.count) games")
    }
}

/// A small stat card: a label, a big value and a plain-language line.
private struct StatTile<Value: View>: View {
    let title: String
    let icon: String
    let tint: Color
    let caption: String
    @ViewBuilder let value: () -> Value

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label {
                Text(title)
            } icon: {
                Image(systemName: icon).foregroundStyle(tint)
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .minimumScaleFactor(0.8)
            value()
                .font(.title2.weight(.bold).monospacedDigit())
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Spacer(minLength: 0)
            Text(caption)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .cardSurface(padding: 12)
        .accessibilityElement(children: .combine)
    }
}
