import Foundation
import SwiftUI

/// A 0-10 performance rating for a single match.
///
/// IMPORTANT: Riot does not publish a per-match rating — the score shown in
/// other companion apps is always that app's own formula, and so is this one.
/// It's a transparent weighted blend of the stats Riot *does* give us, which
/// is why the UI labels it "est." rather than presenting it as official.
///
/// Weighting rationale: carry impact (KDA + share of the team's damage)
/// dominates, presence in fights (kill participation) matters next, and
/// farming/vision are small tie-breakers. Winning nudges it slightly since a
/// stat line that closed out a game is worth more than the same line in a loss.
enum PerformanceScore {
    static func compute(for match: Match) -> Double? {
        guard let stats = match.leagueStats else { return nil }

        let linkedTeamID = match.participants.first(where: \.isLinkedPlayer)?.teamId
        let teammates = match.participants.filter { $0.teamId == linkedTeamID }
        let minutes = max(Double(match.gameDurationSeconds) / 60, 1)

        let teamDamage = teammates.map(\.damageDealtToChampions).reduce(0, +)
        let teamKills = teammates.map(\.kills).reduce(0, +)

        let damageShare = teamDamage > 0
            ? Double(stats.damageDealtToChampions) / Double(teamDamage)
            : 0
        let killParticipation = teamKills > 0
            ? min(Double(stats.kills + stats.assists) / Double(teamKills), 1)
            : 0
        let csPerMinute = Double(stats.creepScore) / minutes
        let visionPerMinute = Double(stats.visionScore) / minutes

        var score = 2.5
        score += min(stats.kda / 5, 1) * 2.0
        score += min(damageShare / 0.35, 1) * 1.5
        score += killParticipation * 1.5
        score += min(csPerMinute / 9, 1) * 0.8
        score += min(visionPerMinute / 1.5, 1) * 0.4
        score += match.win ? 0.5 : -0.5

        return min(max(score, 0), 10)
    }

    /// Same formula applied to any player on the scoreboard, so every one of
    /// the ten gets a comparable number (and MVP/SVP can be picked from it).
    static func compute(for participant: MatchParticipantSummary, in match: Match) -> Double {
        let teammates = match.participants.filter { $0.teamId == participant.teamId }
        let minutes = max(Double(match.gameDurationSeconds) / 60, 1)

        let teamDamage = teammates.map(\.damageDealtToChampions).reduce(0, +)
        let teamKills = teammates.map(\.kills).reduce(0, +)

        let kda = participant.deaths == 0
            ? Double(participant.kills + participant.assists)
            : Double(participant.kills + participant.assists) / Double(participant.deaths)
        let damageShare = teamDamage > 0 ? Double(participant.damageDealtToChampions) / Double(teamDamage) : 0
        let killParticipation = teamKills > 0
            ? min(Double(participant.kills + participant.assists) / Double(teamKills), 1)
            : 0

        var score = 2.5
        score += min(kda / 5, 1) * 2.0
        score += min(damageShare / 0.35, 1) * 1.5
        score += killParticipation * 1.5
        score += min(Double(participant.creepScore) / minutes / 9, 1) * 0.8
        score += min(Double(participant.visionScore) / minutes / 1.5, 1) * 0.4
        score += participant.win ? 0.5 : -0.5

        return min(max(score, 0), 10)
    }

    /// MVP is the best score on the winning side, SVP the best on the losing
    /// side — matching how the reference app labels them.
    static func awards(in match: Match) -> (mvp: String?, svp: String?) {
        let scored = match.participants.map { ($0, compute(for: $0, in: match)) }
        let mvp = scored.filter { $0.0.win }.max { $0.1 < $1.1 }?.0.puuid
        let svp = scored.filter { !$0.0.win }.max { $0.1 < $1.1 }?.0.puuid
        return (mvp, svp)
    }

    /// Where this player placed among all ten, 1-based.
    ///
    /// Ranked on the very number the scoreboard prints beside it, so the badge
    /// and the figure it sits next to can never disagree.
    static func rank(for participant: MatchParticipantSummary, in match: Match) -> Int? {
        let ordered = match.participants
            .map { ($0.puuid, compute(for: $0, in: match)) }
            .sorted { $0.1 > $1.1 }
        guard let index = ordered.firstIndex(where: { $0.0 == participant.puuid }) else { return nil }
        return index + 1
    }

    static func label(for score: Double) -> String {
        switch score {
        case 9...: return "Outstanding"
        case 8..<9: return "Great"
        case 6.5..<8: return "Solid"
        case 5..<6.5: return "Average"
        default: return "Rough"
        }
    }

    /// For tinted text on a normal background.
    static func color(for score: Double) -> Color {
        switch score {
        case 8...: return .orange
        case 6.5..<8: return .green
        case 5..<6.5: return .blue
        default: return .secondary
        }
    }

    /// For a solid chip. Never `.secondary` — a grey fill over champion
    /// splash art is exactly the low-contrast case that made the score
    /// unreadable, so weak scores get a saturated slate instead.
    static func chipColor(for score: Double) -> Color {
        switch score {
        case 8...: return Color(red: 0.85, green: 0.45, blue: 0.10)
        case 6.5..<8: return Color(red: 0.15, green: 0.60, blue: 0.35)
        case 5..<6.5: return Color(red: 0.15, green: 0.40, blue: 0.75)
        default: return Color(red: 0.32, green: 0.34, blue: 0.40)
        }
    }
}
