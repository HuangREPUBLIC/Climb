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

    init(
        teamId: Int,
        win: Bool,
        baronKills: Int = 0,
        dragonKills: Int = 0,
        towerKills: Int = 0,
        inhibitorKills: Int = 0,
        heraldKills: Int = 0,
        voidgrubKills: Int = 0
    ) {
        self.teamId = teamId
        self.win = win
        self.baronKills = baronKills
        self.dragonKills = dragonKills
        self.towerKills = towerKills
        self.inhibitorKills = inhibitorKills
        self.heraldKills = heraldKills
        self.voidgrubKills = voidgrubKills
    }
}
