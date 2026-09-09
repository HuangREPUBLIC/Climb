import Foundation
import SwiftData

/// Head-to-head kill record between the linked player and one specific
/// opponent, reconstructed from Match-V5 timeline `CHAMPION_KILL` events.
/// Riot's aggregate match data can't express this — it only has each
/// player's total K/D/A — so these counts are the difference between
/// "this opponent went 9/7/18" and "you killed *them* twice, died to
/// *them* four times".
@Model
final class OpponentEncounter {
    var opponentPuuid: String
    /// Times the linked player landed the killing blow on this opponent.
    var killsOnOpponent: Int
    /// Times this opponent landed the killing blow on the linked player.
    var deathsToOpponent: Int
    /// Times the linked player assisted a kill on this opponent.
    var assistsOnOpponent: Int

    var match: Match?

    init(
        opponentPuuid: String,
        killsOnOpponent: Int = 0,
        deathsToOpponent: Int = 0,
        assistsOnOpponent: Int = 0
    ) {
        self.opponentPuuid = opponentPuuid
        self.killsOnOpponent = killsOnOpponent
        self.deathsToOpponent = deathsToOpponent
        self.assistsOnOpponent = assistsOnOpponent
    }
}
