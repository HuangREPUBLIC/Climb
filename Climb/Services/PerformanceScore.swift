import Foundation
import SwiftUI

/// A 0-10 match rating. Riot publishes none, so this is Climb's own estimate ("est." in the UI).
/// 1. A raw blend of Riot's stats: carry impact (KDA, damage share) weighs most, then kill
///    participation, then farm and vision. Supports score on vision instead of farm, top laners
///    on damage soaked instead of vision.
/// 2. Stretched against the other nine players, so every lobby averages 5.5 whatever the mode.
/// Calibrated on 19 ranked games against op.gg's OP Score: Spearman 0.93, lobby median 5.4.
enum PerformanceScore {
    /// One player's stats, detached from SwiftData so the formula is a pure function of numbers.
    struct Line {
        let teamId: Int
        let kills: Int
        let deaths: Int
        let assists: Int
        let damage: Int
        let damageTaken: Int
        let creepScore: Int
        let visionScore: Int
        let win: Bool
        let role: String
    }

    static let lobbyAverage = 5.5
    private static let stretch = 1.8

    static func scores(_ lobby: [Line], minutes: Double) -> [Double] {
        let raw = lobby.map { rawScore($0, lobby: lobby, minutes: max(minutes, 1)) }
        let mean = raw.reduce(0, +) / Double(max(raw.count, 1))
        return raw.map { min(max(lobbyAverage + ($0 - mean) * stretch, 0), 10) }
    }

    private static func rawScore(_ line: Line, lobby: [Line], minutes: Double) -> Double {
        let team = lobby.filter { $0.teamId == line.teamId }
        func share(_ part: Int, of whole: Int) -> Double {
            whole > 0 ? Double(part) / Double(whole) : 0
        }
        let kda = Double(line.kills + line.assists) / Double(max(line.deaths, 1))
        let damageShare = share(line.damage, of: team.map(\.damage).reduce(0, +))
        let killParticipation = min(share(line.kills + line.assists, of: team.map(\.kills).reduce(0, +)), 1)
        let visionPerMinute = Double(line.visionScore) / minutes

        var score = 2.5
        score += min(kda / 5, 1) * 2.0
        score += min(damageShare / 0.35, 1) * 1.5
        score += killParticipation * 1.5
        score += line.win ? 0.5 : -0.5
        if line.role == "Support" {
            score += min(visionPerMinute / 2.5, 1) * 1.2
        } else {
            score += min(Double(line.creepScore) / minutes / 9, 1) * 0.8
            score += line.role == "Top"
                ? min(share(line.damageTaken, of: team.map(\.damageTaken).reduce(0, +)) / 0.3, 1) * 0.4
                : min(visionPerMinute / 1.5, 1) * 0.4
        }
        return score
    }

    /// The match's performance-card score: the linked player's, or the browsed profile's player.
    static func compute(for match: Match) -> Double? {
        guard let player = match.focusParticipant else { return nil }
        return compute(for: player, in: match)
    }

    static func compute(for participant: MatchParticipantSummary, in match: Match) -> Double {
        guard let index = match.participants.firstIndex(where: { $0 === participant }) else { return lobbyAverage }
        return lobbyScores(in: match)[index]
    }

    /// All scores in `match.participants` order, so awards and ranks score the lobby only once.
    static func lobbyScores(in match: Match) -> [Double] {
        let lobby = match.participants.map {
            Line(
                teamId: $0.teamId, kills: $0.kills, deaths: $0.deaths, assists: $0.assists,
                damage: $0.damageDealtToChampions, damageTaken: $0.damageTaken,
                creepScore: $0.creepScore, visionScore: $0.visionScore, win: $0.win, role: $0.role
            )
        }
        return scores(lobby, minutes: Double(match.gameDurationSeconds) / 60)
    }

    #if DEBUG
    /// Runs on every debug launch; fails loudly if a formula change breaks its promises.
    static func selfCheck() {
        func line(team: Int, k: Int, d: Int, a: Int, dmg: Int, cs: Int, vision: Int, win: Bool, role: String = "Mid") -> Line {
            Line(teamId: team, kills: k, deaths: d, assists: a, damage: dmg, damageTaken: 20_000,
                 creepScore: cs, visionScore: vision, win: win, role: role)
        }
        let lobby = [
            line(team: 100, k: 12, d: 1, a: 8, dmg: 40_000, cs: 260, vision: 25, win: true),
            line(team: 100, k: 4, d: 4, a: 6, dmg: 18_000, cs: 200, vision: 20, win: true),
            line(team: 100, k: 3, d: 5, a: 7, dmg: 15_000, cs: 180, vision: 18, win: true),
            line(team: 100, k: 2, d: 4, a: 9, dmg: 14_000, cs: 170, vision: 22, win: true),
            line(team: 100, k: 1, d: 3, a: 18, dmg: 8_000, cs: 30, vision: 80, win: true, role: "Support"),
            line(team: 200, k: 1, d: 10, a: 2, dmg: 9_000, cs: 120, vision: 10, win: false),
            line(team: 200, k: 4, d: 5, a: 4, dmg: 17_000, cs: 190, vision: 18, win: false),
            line(team: 200, k: 3, d: 5, a: 5, dmg: 16_000, cs: 185, vision: 19, win: false),
            line(team: 200, k: 3, d: 4, a: 5, dmg: 15_000, cs: 175, vision: 20, win: false),
            line(team: 200, k: 1, d: 5, a: 8, dmg: 6_000, cs: 25, vision: 60, win: false, role: "Support"),
        ]
        let s = scores(lobby, minutes: 30)
        assert(abs(s.reduce(0, +) / Double(s.count) - lobbyAverage) < 0.3, "lobby should average 5.5: \(s)")
        assert(s[0] > 8.5 && s[5] < 3, "carry and feeder should be far apart: \(s)")
        assert(s[4] > s[3], "a high-vision support shouldn't trail a quiet laner: \(s)")
    }
    #endif

    /// MVP: best score on the winning side; SVP: best on the losing side (op.gg's labels).
    static func awards(in match: Match) -> (mvp: String?, svp: String?) {
        let scored = Array(zip(match.participants, lobbyScores(in: match)))
        let mvp = scored.filter { $0.0.win }.max { $0.1 < $1.1 }?.0.puuid
        let svp = scored.filter { !$0.0.win }.max { $0.1 < $1.1 }?.0.puuid
        return (mvp, svp)
    }

    /// 1-based place among all ten, ranked on the printed score so badge and figure can't disagree.
    static func rank(for participant: MatchParticipantSummary, in match: Match) -> Int? {
        let ordered = zip(match.participants.map(\.puuid), lobbyScores(in: match))
            .sorted { $0.1 > $1.1 }
        guard let index = ordered.firstIndex(where: { $0.0 == participant.puuid }) else { return nil }
        return index + 1
    }

    /// 6+ green, 4-6 yellow, under 4 red (the 5.5 average reads yellow), banded on the one-decimal
    /// figure shown so a 3.96 printed as "4.0" isn't red.
    static func color(for score: Double) -> Color {
        let shown = (score * 10).rounded() / 10
        return shown >= 6 ? Theme.good : shown >= 4 ? Theme.fair : Theme.poor
    }
}
