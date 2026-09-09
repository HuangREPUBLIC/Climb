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

    init(
        champion: String,
        role: String,
        kills: Int,
        deaths: Int,
        assists: Int,
        creepScore: Int,
        items: [Int] = [],
        summonerSpellIDs: [Int] = [],
        goldEarned: Int = 0,
        damageDealtToChampions: Int = 0,
        damageTaken: Int = 0,
        visionScore: Int = 0,
        wardsPlaced: Int = 0,
        keystoneID: Int = 0,
        primaryStyleID: Int = 0,
        subStyleID: Int = 0,
        doubleKills: Int = 0,
        tripleKills: Int = 0,
        quadraKills: Int = 0,
        pentaKills: Int = 0,
        turretKills: Int = 0,
        inhibitorKills: Int = 0,
        dragonKills: Int = 0,
        dragonKillsByType: [String: Int] = [:],
        baronKills: Int = 0,
        objectivesStolen: Int = 0,
        riftHeraldKills: Int = 0,
        voidgrubKills: Int = 0,
        firstBloodKill: Bool = false,
        largestKillingSpree: Int = 0,
        wardsKilled: Int = 0,
        soloKills: Int = 0
    ) {
        self.champion = champion
        self.role = role
        self.kills = kills
        self.deaths = deaths
        self.assists = assists
        self.creepScore = creepScore
        self.items = items
        self.summonerSpellIDs = summonerSpellIDs
        self.goldEarned = goldEarned
        self.damageDealtToChampions = damageDealtToChampions
        self.damageTaken = damageTaken
        self.visionScore = visionScore
        self.wardsPlaced = wardsPlaced
        self.keystoneID = keystoneID
        self.primaryStyleID = primaryStyleID
        self.subStyleID = subStyleID
        self.doubleKills = doubleKills
        self.tripleKills = tripleKills
        self.quadraKills = quadraKills
        self.pentaKills = pentaKills
        self.turretKills = turretKills
        self.inhibitorKills = inhibitorKills
        self.dragonKills = dragonKills
        self.dragonKillsByType = dragonKillsByType
        self.baronKills = baronKills
        self.objectivesStolen = objectivesStolen
        self.riftHeraldKills = riftHeraldKills
        self.voidgrubKills = voidgrubKills
        self.firstBloodKill = firstBloodKill
        self.largestKillingSpree = largestKillingSpree
        self.wardsKilled = wardsKilled
        self.soloKills = soloKills
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
