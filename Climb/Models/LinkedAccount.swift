import Foundation
import SwiftData

@Model
final class LinkedAccount {
    var riotGameName: String
    var riotTagline: String
    var region: String
    var platform: String = ""
    var profileIconID: Int?
    var summonerLevel: Int?
    var rankTier: String?
    var rankDivision: String?
    var leaguePoints: Int?
    var rankWins: Int?
    var rankLosses: Int?
    var syncedGameRawValues: [String]
    var lastLeagueSyncDate: Date?
    /// When Riot last saw activity on this account, from Summoner-V4's
    /// `revisionDate`. Compared against the newest imported match to tell an
    /// unpublished-match gap apart from an app that simply hasn't synced.
    var lastRiotActivityDate: Date?
    var lastTFTSyncDate: Date?

    init(
        riotGameName: String,
        riotTagline: String,
        region: String,
        platform: String = "",
        syncedGames: [Game] = [.league]
    ) {
        self.riotGameName = riotGameName
        self.riotTagline = riotTagline
        self.region = region
        self.platform = platform
        self.syncedGameRawValues = syncedGames.map(\.rawValue)
    }

    var syncedGames: [Game] {
        get { syncedGameRawValues.compactMap(Game.init(rawValue:)) }
        set { syncedGameRawValues = newValue.map(\.rawValue) }
    }

    var riotID: String { "\(riotGameName)#\(riotTagline)" }

    func lastSyncDate(for game: Game) -> Date? {
        switch game {
        case .league: return lastLeagueSyncDate
        case .tft: return lastTFTSyncDate
        }
    }
}
