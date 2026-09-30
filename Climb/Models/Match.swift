import Foundation
import SwiftData

@Model
final class Match {
    @Attribute(.unique) var id: String
    var game: Game
    var win: Bool
    var queueType: String
    /// Riot's raw queue id, kept alongside the display name so views can
    /// branch on the actual mode rather than
    /// string-matching the label.
    var queueId: Int = 0
    var gameDurationSeconds: Int
    var timestamp: Date
    var notes: String
    var tags: [String]
    /// `MatchImportService.currentDataVersion` of the import that built this
    /// match's scoreboard. Anything lower is rebuilt in place on the next sync.
    var importVersion: Int = 0
    /// False for a match browsed from another player's profile. Those are a
    /// cache of someone else's game, so they are excluded from every list that
    /// means "games I played" — the match list, the profile, and the stats.
    var isOwnHistory: Bool = true
    /// The AI review card's text, generated once when the match is first
    /// opened (see `CoachService.review`).
    var reviewText: String?

    @Relationship(deleteRule: .cascade, inverse: \LeagueStats.match)
    var leagueStats: LeagueStats?

    @Relationship(deleteRule: .cascade, inverse: \TFTStats.match)
    var tftStats: TFTStats?

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
        tags: [String] = []
    ) {
        self.id = id
        self.game = game
        self.win = win
        self.queueType = queueType
        self.gameDurationSeconds = gameDurationSeconds
        self.timestamp = timestamp
        self.notes = notes
        self.tags = tags
    }
}

extension Match {
    /// Whose game this screen is about: the linked player in your own history,
    /// or, on a copy browsed from someone's profile, that player — whose puuid
    /// the copy's id carries (`browsed:<puuid>:<matchId>`).
    var focusParticipant: MatchParticipantSummary? {
        if let me = participants.first(where: \.isLinkedPlayer) { return me }
        let parts = id.split(separator: ":")
        guard parts.count == 3 else { return nil }
        return participants.first { $0.puuid == parts[1] }
    }

    /// Game length in minutes, floored at one so a remake can't divide by zero.
    var minutes: Double { max(Double(gameDurationSeconds) / 60, 1) }

    /// The enemy in the same role — the only fair comparison for farm and
    /// lane fights. Nil in modes without lanes.
    func laneOpponent(of player: MatchParticipantSummary) -> MatchParticipantSummary? {
        guard player.role != "—" else { return nil }
        return participants.first { $0.teamId != player.teamId && $0.role == player.role }
    }

    /// The server the game was played on, from Riot's match-id prefix
    /// ("JP1_603518261" is .jp1), so a game browsed from another server's
    /// player looks its players up there rather than on your own.
    var platform: RiotPlatform? {
        let riotID = id.split(separator: ":").last.map(String.init) ?? id
        return riotID.split(separator: "_").first.flatMap { RiotPlatform(rawValue: $0.lowercased()) }
    }
}
