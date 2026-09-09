import Foundation
import SwiftData

@Model
final class Match {
    @Attribute(.unique) var id: String
    var game: Game
    var win: Bool
    var queueType: String
    /// Riot's raw queue id, kept alongside the display name so views can
    /// branch on the actual mode (augment modes, ARAM, Arena) rather than
    /// string-matching the label.
    var queueId: Int = 0
    var gameDurationSeconds: Int
    var timestamp: Date
    var notes: String
    var tags: [String]
    var isMockData: Bool = false
    /// False for a match browsed from another player's profile. Those are a
    /// cache of someone else's game, so they are excluded from every list that
    /// means "games I played" — the match list, the profile, and the stats.
    var isOwnHistory: Bool = true

    @Relationship(deleteRule: .cascade, inverse: \LeagueStats.match)
    var leagueStats: LeagueStats?

    @Relationship(deleteRule: .cascade, inverse: \TFTStats.match)
    var tftStats: TFTStats?

    @Relationship(deleteRule: .cascade, inverse: \ValorantStats.match)
    var valorantStats: ValorantStats?

    @Relationship(deleteRule: .cascade, inverse: \CoachConversation.match)
    var coachConversation: CoachConversation?

    @Relationship(deleteRule: .cascade, inverse: \MatchParticipantSummary.match)
    var participants: [MatchParticipantSummary] = []

    @Relationship(deleteRule: .cascade, inverse: \TeamStats.match)
    var teamStats: [TeamStats] = []

    @Relationship(deleteRule: .cascade, inverse: \OpponentEncounter.match)
    var opponentEncounters: [OpponentEncounter] = []

    @Relationship(deleteRule: .cascade, inverse: \GoldTimelinePoint.match)
    var goldTimeline: [GoldTimelinePoint] = []

    init(
        id: String,
        game: Game,
        win: Bool,
        queueType: String,
        gameDurationSeconds: Int,
        timestamp: Date,
        notes: String = "",
        tags: [String] = [],
        isMockData: Bool = false
    ) {
        self.id = id
        self.game = game
        self.win = win
        self.queueType = queueType
        self.gameDurationSeconds = gameDurationSeconds
        self.timestamp = timestamp
        self.notes = notes
        self.tags = tags
        self.isMockData = isMockData
    }
}
