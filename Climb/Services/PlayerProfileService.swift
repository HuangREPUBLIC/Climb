import Foundation

/// Identity + rank for another player, so their page can open on a profile
/// like the linked account's own rather than a bare list of games.
struct OtherPlayerProfile {
    let profileIconID: Int?
    let summonerLevel: Int?
    let rankTier: String?
    let rankDivision: String?
    let leaguePoints: Int?
    let rankWins: Int?
    let rankLosses: Int?
}

enum PlayerProfileService {
    static func profile(puuid: String, platform: RiotPlatform) async -> OtherPlayerProfile {
        let client = RiotAPIClient.shared
        let summoner = try? await client.fetchSummoner(puuid: puuid, platform: platform)
        let entries = try? await client.fetchLeagueEntries(puuid: puuid, platform: platform)
        let solo = entries?.first { $0.queueType == "RANKED_SOLO_5x5" }

        return OtherPlayerProfile(
            profileIconID: summoner?.profileIconId,
            summonerLevel: summoner?.summonerLevel,
            rankTier: solo?.tier,
            rankDivision: solo?.rank,
            leaguePoints: solo?.leaguePoints,
            rankWins: solo?.wins,
            rankLosses: solo?.losses
        )
    }
}
