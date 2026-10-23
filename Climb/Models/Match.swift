import Foundation
import SwiftData

@Model
final class Match {
    @Attribute(.unique) var id: String
    var game: Game
    var win: Bool
    var queueType: String
    /// Riot's raw queue id, so views branch on the mode instead of string-matching the label.
    var queueId: Int = 0
    var gameDurationSeconds: Int
    var timestamp: Date
    var notes: String
    var tags: [String]
    /// `currentDataVersion` of the import that built this match; lower is rebuilt on the next sync.
    var importVersion: Int = 0
    /// False for a game browsed from another player's profile: kept out of every "my games" list.
    var isOwnHistory: Bool = true
    /// Listed under Saved Games; nothing cleans it up (see `MatchImportService.removeFromHistory`).
    var isSaved: Bool = false
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
    /// Whose game this is: the linked player, or on a browsed copy the player whose puuid its id
    /// carries (`browsed:<puuid>:<matchId>`).
    var focusParticipant: MatchParticipantSummary? {
        if let me = participants.first(where: \.isLinkedPlayer) { return me }
        let parts = id.split(separator: ":")
        guard parts.count == 3 else { return nil }
        return participants.first { $0.puuid == parts[1] }
    }

    /// Game length in minutes, floored at one so a remake can't divide by zero.
    var minutes: Double { max(Double(gameDurationSeconds) / 60, 1) }

    /// The enemy in the same role, the fair comparison for farm and fights; nil without lanes.
    func laneOpponent(of player: MatchParticipantSummary) -> MatchParticipantSummary? {
        guard player.role != "—" else { return nil }
        return participants.first { $0.teamId != player.teamId && $0.role == player.role }
    }

    /// Kill participation as a fraction, (kills + assists) / team kills; nil if the team had none.
    func killShare(of player: MatchParticipantSummary) -> Double? {
        let teamKills = participants.filter { $0.teamId == player.teamId }.map(\.kills).reduce(0, +)
        return teamKills > 0 ? Double(player.kills + player.assists) / Double(teamKills) : nil
    }

    /// The server the game was played on, from the match-id prefix ("JP1_603518261" is .jp1), so
    /// players of a game browsed from another server are looked up there.
    var platform: RiotPlatform? {
        let riotID = id.split(separator: ":").last.map(String.init) ?? id
        return riotID.split(separator: "_").first.flatMap { RiotPlatform(rawValue: $0.lowercased()) }
    }
}

extension Array where Element == Match {
    var queuesByPlays: [String] {
        Dictionary(grouping: self, by: \.queueType)
            .sorted { $0.value.count > $1.value.count }
            .map(\.key)
    }
}
