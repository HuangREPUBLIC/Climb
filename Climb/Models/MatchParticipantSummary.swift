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

    init(_ p: RiotMatchResponse.Participant, role: String, isLinkedPlayer: Bool) {
        puuid = p.puuid
        riotIdGameName = p.riotIdGameName
        riotIdTagline = p.riotIdTagline
        teamId = p.teamId
        champion = p.championName
        self.role = role
        kills = p.kills
        deaths = p.deaths
        assists = p.assists
        win = p.win
        items = p.items
        goldEarned = p.goldEarned
        damageDealtToChampions = p.totalDamageDealtToChampions
        damageTaken = p.totalDamageTaken
        totalHeal = p.totalHeal
        creepScore = p.totalMinionsKilled + p.neutralMinionsKilled
        visionScore = p.visionScore
        wardsPlaced = p.wardsPlaced
        wardsKilled = p.wardsKilled ?? 0
        largestMultiKill = p.largestMultiKill ?? 0
        largestKillingSpree = p.largestKillingSpree ?? 0
        turretKills = p.turretKills ?? 0
        summonerSpellIDs = [p.summoner1Id, p.summoner2Id]
        keystoneID = p.perks.keystoneID
        primaryRuneIDs = p.perks.primaryRuneIDs
        secondaryRuneIDs = p.perks.secondaryRuneIDs
        primaryStyleID = p.perks.primaryStyleID
        subStyleID = p.perks.subStyleID
        statPerkIDs = p.perks.statPerkIDs
        champLevel = p.champLevel ?? 0
        self.isLinkedPlayer = isLinkedPlayer
    }
}

extension MatchParticipantSummary {
    /// Same rule as `LeagueStats.kda`: a deathless game counts takedowns.
    var kda: Double {
        deaths == 0 ? Double(kills + assists) : Double(kills + assists) / Double(deaths)
    }

    /// The linked player, in a game that still counts as theirs. A saved game
    /// kept from an earlier login keeps `isLinkedPlayer`, which its focus
    /// depends on, but stops saying "You".
    var isYou: Bool { isLinkedPlayer && match?.isOwnHistory == true }
}
