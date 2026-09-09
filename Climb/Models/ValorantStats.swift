import Foundation
import SwiftData

@Model
final class ValorantStats {
    var agent: String
    var map: String
    var kills: Int
    var deaths: Int
    var assists: Int
    var combatScore: Int

    var match: Match?

    init(agent: String, map: String, kills: Int, deaths: Int, assists: Int, combatScore: Int) {
        self.agent = agent
        self.map = map
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.combatScore = combatScore
    }
}
