import Foundation

/// VAL-MATCH-V1 response shape. `characterId`/`mapId` are Riot content UUIDs,
/// not display names — resolving them to "Jett"/"Ascent" etc. needs a
/// VAL-CONTENT-V1 lookup, not yet built since this endpoint can't be called
/// or tested without elevated API access.
struct RiotValorantMatchResponse: Decodable {
    let matchInfo: MatchInfo
    let players: [Player]

    struct MatchInfo: Decodable {
        let matchId: String
        let mapId: String
        let gameLengthMillis: Int
        let gameStartMillis: Int64
        let queueId: String
    }

    struct Player: Decodable {
        let puuid: String
        let characterId: String
        let stats: Stats

        struct Stats: Decodable {
            let kills: Int
            let deaths: Int
            let assists: Int
            let score: Int
        }
    }
}
