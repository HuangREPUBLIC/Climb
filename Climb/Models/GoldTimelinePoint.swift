import Foundation
import SwiftData

/// One minute of the match's gold/XP curve, summed per team.
///
/// Riot only exposes this through the timeline endpoint's `participantFrames`
/// (one snapshot per frame, roughly a minute apart), which is why it has to be
/// captured at import time rather than derived from the match summary.
@Model
final class GoldTimelinePoint {
    /// Minutes since game start.
    var minute: Int
    var allyGold: Int
    var enemyGold: Int
    var allyXP: Int
    var enemyXP: Int

    var match: Match?

    /// Positive means the linked player's team was ahead at this minute.
    var goldDifference: Int { allyGold - enemyGold }

    init(minute: Int, allyGold: Int, enemyGold: Int, allyXP: Int = 0, enemyXP: Int = 0) {
        self.minute = minute
        self.allyGold = allyGold
        self.enemyGold = enemyGold
        self.allyXP = allyXP
        self.enemyXP = enemyXP
    }
}
