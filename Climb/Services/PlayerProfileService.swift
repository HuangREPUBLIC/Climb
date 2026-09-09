import Foundation

/// Read-only lookup of another player's recent matches, by puuid — used when
/// tapping a teammate/opponent in a scoreboard. Deliberately does not touch
/// SwiftData: this is someone else's data, not the linked player's own
/// journal, so nothing here is persisted.
struct OtherPlayerMatchSummary: Identifiable {
    let id: String
    let champion: String
    let role: String
    let kills: Int
    let deaths: Int
    let assists: Int
    let win: Bool
    let queueType: String
    let timestamp: Date
}

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

    /// `start` lets the view page through the player's full history instead of
    /// being capped at the first handful of games.
    static func recentMatches(
        puuid: String,
        region: RiotRegion,
        start: Int = 0,
        count: Int = 15
    ) async throws -> [OtherPlayerMatchSummary] {
        let client = RiotAPIClient.shared
        let matchIDs = try await client.fetchRecentMatchIDs(puuid: puuid, region: region, start: start, count: count)

        var summaries: [OtherPlayerMatchSummary] = []
        for matchID in matchIDs {
            do {
                let detail = try await client.fetchMatch(matchID: matchID, region: region)
                guard let participant = detail.info.participants.first(where: { $0.puuid == puuid }) else { continue }
                summaries.append(
                    OtherPlayerMatchSummary(
                        id: detail.metadata.matchId,
                        champion: participant.championName,
                        role: participant.teamPosition,
                        kills: participant.kills,
                        deaths: participant.deaths,
                        assists: participant.assists,
                        win: participant.win,
                        queueType: queueTypeName(for: detail.info.queueId),
                        timestamp: Date(timeIntervalSince1970: Double(detail.info.gameCreation) / 1000)
                    )
                )
            } catch RiotAPIError.rateLimited {
                break
            } catch {
                continue
            }
        }
        return summaries
    }

    /// Shared with the importer so another player's matches show the same
    /// mode names as your own instead of a stale five-entry table.
    private static func queueTypeName(for queueId: Int) -> String {
        MatchImportService.queueTypeName(for: queueId)
    }
}
