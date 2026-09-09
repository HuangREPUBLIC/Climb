import Foundation

/// Riot's own Data Dragon doesn't host ranked-tier emblem art (a known gap),
/// so this pulls from CommunityDragon — a community-maintained static asset
/// mirror, not an official Riot source. It only serves decorative tier icons
/// (Iron/Bronze/.../Challenger), not match or player data, so it doesn't
/// touch the "official API only" boundary the rest of this app holds to.
enum RankEmblemService {
    nonisolated static func emblemURL(for tier: String) -> URL? {
        let normalized = tier.lowercased()
        return URL(string: "https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-static-assets/global/default/ranked-emblem/emblem-\(normalized).png")
    }

    private static let noDivisionTiers: Set<String> = ["MASTER", "GRANDMASTER", "CHALLENGER"]

    static func displayName(tier: String, division: String) -> String {
        let tierName = tier.capitalized
        if noDivisionTiers.contains(tier.uppercased()) {
            return tierName
        }
        return "\(tierName) \(division)"
    }
}
