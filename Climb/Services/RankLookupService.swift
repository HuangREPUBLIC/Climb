import Foundation

/// On-demand rank lookup for other players in a scoreboard (not persisted —
/// rank is always-current, not a property of the historical match, and this
/// isn't the linked player's own data to journal).
enum RankLookupService {
    /// Tier plus division, so the scoreboard can print "IV" beside the emblem
    /// the way the in-game and reference-app scoreboards do.
    struct SoloRank {
        let tier: String
        let division: String
    }

    static func fetchSoloRank(puuid: String, platform: RiotPlatform) async -> SoloRank? {
        guard let entries = try? await RiotAPIClient.shared.fetchLeagueEntries(puuid: puuid, platform: platform),
              let solo = entries.first(where: { $0.queueType == "RANKED_SOLO_5x5" })
        else { return nil }
        return SoloRank(tier: solo.tier, division: solo.rank)
    }

    static func fetchSoloTier(puuid: String, platform: RiotPlatform) async -> String? {
        await fetchSoloRank(puuid: puuid, platform: platform)?.tier
    }
}
