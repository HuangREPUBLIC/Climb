import Foundation
import SwiftData

@Model
final class LeagueStats {
    var champion: String
    var role: String
    var kills: Int
    var deaths: Int
    var assists: Int
    var creepScore: Int
    var items: [Int] = []
    var summonerSpellIDs: [Int] = []
    var goldEarned: Int = 0
    var damageDealtToChampions: Int = 0
    var damageTaken: Int = 0
    var visionScore: Int = 0
    var wardsPlaced: Int = 0
    var keystoneID: Int = 0
    var primaryStyleID: Int = 0
    var subStyleID: Int = 0
    var doubleKills: Int = 0
    var tripleKills: Int = 0
    var quadraKills: Int = 0
    var pentaKills: Int = 0

    // Advanced stats — all default to 0/false so matches imported before
    // these were tracked keep loading; a re-sync backfills them.
    // Objective counts are "how many this player personally killed/destroyed".
    var turretKills: Int = 0
    var inhibitorKills: Int = 0
    var dragonKills: Int = 0
    /// Dragons broken out by element, keyed by Riot's `monsterSubType`
    /// (FIRE_DRAGON, WATER_DRAGON, ELDER_DRAGON, …) since each drake type
    /// means something different and deserves its own icon.
    var dragonKillsByType: [String: Int] = [:]
    var baronKills: Int = 0
    var objectivesStolen: Int = 0
    /// Rift Herald and Voidgrub credit only exists in timeline events.
    var riftHeraldKills: Int = 0
    var voidgrubKills: Int = 0
    var firstBloodKill: Bool = false
    var largestKillingSpree: Int = 0
    var wardsKilled: Int = 0
    /// Kills with no assisting teammate — derived from timeline events.
    var soloKills: Int = 0

    var match: Match?

    /// The timeline-only fields (drakes by type, Herald, Voidgrubs, solo kills)
    /// keep their defaults here; `MatchImportService.importHeadToHead` fills them.
    init(_ p: RiotMatchResponse.Participant, role: String) {
        champion = p.championName
        self.role = role
        kills = p.kills
        deaths = p.deaths
        assists = p.assists
        creepScore = p.totalMinionsKilled + p.neutralMinionsKilled
        items = p.items
        summonerSpellIDs = [p.summoner1Id, p.summoner2Id]
        goldEarned = p.goldEarned
        damageDealtToChampions = p.totalDamageDealtToChampions
        damageTaken = p.totalDamageTaken
        visionScore = p.visionScore
        wardsPlaced = p.wardsPlaced
        keystoneID = p.perks.keystoneID
        primaryStyleID = p.perks.primaryStyleID
        subStyleID = p.perks.subStyleID
        doubleKills = p.doubleKills
        tripleKills = p.tripleKills
        quadraKills = p.quadraKills
        pentaKills = p.pentaKills
        turretKills = p.turretKills ?? 0
        inhibitorKills = p.inhibitorKills ?? 0
        dragonKills = p.dragonKills ?? 0
        baronKills = p.baronKills ?? 0
        objectivesStolen = p.objectivesStolen ?? 0
        firstBloodKill = p.firstBloodKill ?? false
        largestKillingSpree = p.largestKillingSpree ?? 0
        wardsKilled = p.wardsKilled ?? 0
    }

    var kda: Double {
        deaths == 0 ? Double(kills + assists) : Double(kills + assists) / Double(deaths)
    }

    var multiKillLabel: String? {
        if pentaKills > 0 { return "Pentakill!" }
        if quadraKills > 0 { return "Quadra Kill" }
        if tripleKills > 0 { return "Triple Kill" }
        if doubleKills > 0 { return "Double Kill" }
        return nil
    }
}
