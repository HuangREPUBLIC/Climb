import Foundation
import SwiftData

/// One row of the post-game scoreboard — all 10 League players, not just
/// the linked account's own row (that fuller detail lives on LeagueStats).
@Model
final class MatchParticipantSummary {
    var puuid: String
    var riotIdGameName: String
    var riotIdTagline: String
    var teamId: Int
    var champion: String
    var role: String = ""
    var kills: Int
    var deaths: Int
    var assists: Int
    var win: Bool
    var items: [Int]
    var goldEarned: Int = 0
    var damageDealtToChampions: Int = 0
    var damageTaken: Int = 0
    var totalHeal: Int = 0
    var creepScore: Int = 0
    // Needed so the expanded head-to-head panel can compare any two players,
    // not just the linked account (whose detail lives on LeagueStats).
    var visionScore: Int = 0
    var wardsPlaced: Int = 0
    var wardsKilled: Int = 0
    var largestMultiKill: Int = 0
    var largestKillingSpree: Int = 0
    var turretKills: Int = 0
    var summonerSpellIDs: [Int] = []
    var keystoneID: Int = 0
    /// Every primary-tree pick (keystone first) and both secondary picks, so
    /// the scoreboard can show a full rune page rather than just the keystone.
    var primaryRuneIDs: [Int] = []
    var secondaryRuneIDs: [Int] = []
    var primaryStyleID: Int = 0
    var subStyleID: Int = 0
    /// Offence, flex and defence shard, in that order — Riot's own row order.
    var statPerkIDs: [Int] = []
    var champLevel: Int = 0
    var isLinkedPlayer: Bool

    var match: Match?

    init(
        puuid: String,
        riotIdGameName: String,
        riotIdTagline: String,
        teamId: Int,
        champion: String,
        role: String = "",
        kills: Int,
        deaths: Int,
        assists: Int,
        win: Bool,
        items: [Int],
        goldEarned: Int = 0,
        damageDealtToChampions: Int = 0,
        damageTaken: Int = 0,
        totalHeal: Int = 0,
        creepScore: Int = 0,
        visionScore: Int = 0,
        wardsPlaced: Int = 0,
        wardsKilled: Int = 0,
        largestMultiKill: Int = 0,
        largestKillingSpree: Int = 0,
        turretKills: Int = 0,
        summonerSpellIDs: [Int] = [],
        keystoneID: Int = 0,
        primaryRuneIDs: [Int] = [],
        secondaryRuneIDs: [Int] = [],
        primaryStyleID: Int = 0,
        subStyleID: Int = 0,
        statPerkIDs: [Int] = [],
        champLevel: Int = 0,
        isLinkedPlayer: Bool
    ) {
        self.puuid = puuid
        self.riotIdGameName = riotIdGameName
        self.riotIdTagline = riotIdTagline
        self.teamId = teamId
        self.champion = champion
        self.role = role
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.win = win
        self.items = items
        self.goldEarned = goldEarned
        self.damageDealtToChampions = damageDealtToChampions
        self.damageTaken = damageTaken
        self.totalHeal = totalHeal
        self.creepScore = creepScore
        self.visionScore = visionScore
        self.wardsPlaced = wardsPlaced
        self.wardsKilled = wardsKilled
        self.largestMultiKill = largestMultiKill
        self.largestKillingSpree = largestKillingSpree
        self.turretKills = turretKills
        self.summonerSpellIDs = summonerSpellIDs
        self.keystoneID = keystoneID
        self.primaryRuneIDs = primaryRuneIDs
        self.secondaryRuneIDs = secondaryRuneIDs
        self.primaryStyleID = primaryStyleID
        self.subStyleID = subStyleID
        self.statPerkIDs = statPerkIDs
        self.champLevel = champLevel
        self.isLinkedPlayer = isLinkedPlayer
    }
}

extension MatchParticipantSummary {
    /// Same rule as `LeagueStats.kda`: a deathless game counts takedowns.
    var kda: Double {
        deaths == 0 ? Double(kills + assists) : Double(kills + assists) / Double(deaths)
    }
}
