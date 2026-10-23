import Foundation
import SwiftData

/// Team-level objective totals from Match-V5 (`info.teams[].objectives`) —
/// not derivable from individual participants, so stored separately.
@Model
final class TeamStats {
    var teamId: Int
    var win: Bool
    var baronKills: Int = 0
    var dragonKills: Int = 0
    var towerKills: Int = 0
    var inhibitorKills: Int = 0
    var heraldKills: Int = 0
    /// Voidgrubs. Riot calls them `horde`.
    var voidgrubKills: Int = 0

    var match: Match?

    init(_ team: RiotMatchResponse.Team) {
        teamId = team.teamId
        win = team.win
        baronKills = team.objectives.baron.kills
        dragonKills = team.objectives.dragon.kills
        towerKills = team.objectives.tower.kills
        inhibitorKills = team.objectives.inhibitor.kills
        heraldKills = team.objectives.riftHerald.kills
        voidgrubKills = team.objectives.horde?.kills ?? 0
    }
}
