import Foundation

/// How a ranked tier is written. The emblems themselves are bundled; see
/// RankIconView.
enum RankEmblemService {
    private static let noDivisionTiers: Set<String> = ["MASTER", "GRANDMASTER", "CHALLENGER"]

    static func displayName(tier: String, division: String) -> String {
        let tierName = tier.capitalized
        if noDivisionTiers.contains(tier.uppercased()) {
            return tierName
        }
        return "\(tierName) \(division)"
    }
}
