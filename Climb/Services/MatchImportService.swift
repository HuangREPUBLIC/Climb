import Foundation
import SwiftData
import CryptoKit

@MainActor
enum MatchImportService {
    /// Bump whenever the import writes fields older records don't have —
    /// forgetting to bump is why a new field silently stays zero.
    /// v1: base stats · v2: timeline head-to-head, gold curve, advanced stats
    /// · v3: per-participant vision/wards/multikill/spree/turrets, runes,
    /// summoner spells and champion level for every player on the scoreboard
    /// · v4: full paged history, raw queueId, real queue names, augment picks
    /// · v5: complete rune pages (all primary + secondary picks, not just the
    /// keystone) for every player.
    static let currentDataVersion = 9

    /// PUUIDs are encrypted per API key: Riot answers a lookup made with a
    /// different key than the one that issued the id with
    /// "Bad Request - Exception decrypting …". So a key change invalidates
    /// every stored PUUID and the matches have to be re-imported, otherwise
    /// every rank lookup and player profile 400s.
    private static let apiKeyFingerprintDefaultsKey = "riotAPIKeyFingerprint"

    private static var storedKeyFingerprint: String? {
        get { UserDefaults.standard.string(forKey: apiKeyFingerprintDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyFingerprintDefaultsKey) }
    }

    /// Only a short digest is persisted — never the key itself.
    ///
    /// SHA-256 rather than `Hasher`/`hashValue`: Swift seeds those randomly
    /// per process, so the same key would hash differently on every launch and
    /// trigger a full re-import every time the app opened.
    private static var currentKeyFingerprint: String {
        let digest = SHA256.hash(data: Data(Secrets.riotAPIKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    static var apiKeyChangedSinceLastImport: Bool {
        storedKeyFingerprint != currentKeyFingerprint
    }

    /// Re-imports everything for the already-linked account when its stored
    /// data predates the current import logic. Without this, newly added
    /// fields stay blank forever on existing matches — the user has no way to
    /// force a backfill from the UI, since a normal sync only fetches *new*
    /// match IDs.
    static func refreshIfNeeded(context: ModelContext) async {
        guard let account = try? context.fetch(FetchDescriptor<LinkedAccount>()).first,
              account.dataSchemaVersion < currentDataVersion || apiKeyChangedSinceLastImport,
              let platform = RiotPlatform(rawValue: account.platform)
        else { return }

        try? await linkAndSync(
            gameName: account.riotGameName,
            tagLine: account.riotTagline,
            platform: platform,
            gamesToSync: Set(account.syncedGames),
            context: context,
            rebuildExisting: true
        )
    }

    static func linkAndSync(
        gameName: String,
        tagLine: String,
        platform: RiotPlatform,
        gamesToSync: Set<Game>,
        context: ModelContext,
        rebuildExisting: Bool = false
    ) async throws {
        let region = platform.region
        let client = RiotAPIClient.shared
        let puuid = try await client.resolvePUUID(gameName: gameName, tagLine: tagLine, region: region)
        let summoner = try? await client.fetchSummoner(puuid: puuid, platform: platform)
        let soloRank = try? await client.fetchLeagueEntries(puuid: puuid, platform: platform)
            .first { $0.queueType == "RANKED_SOLO_5x5" }

        let account: LinkedAccount
        if let existing = try context.fetch(FetchDescriptor<LinkedAccount>()).first {
            existing.riotGameName = gameName
            existing.riotTagline = tagLine
            existing.region = region.rawValue
            existing.platform = platform.rawValue
            existing.syncedGames = Array(gamesToSync)
            if let summoner {
                existing.profileIconID = summoner.profileIconId
                existing.summonerLevel = summoner.summonerLevel
                existing.lastRiotActivityDate = summoner.revisionDate.map { Date(timeIntervalSince1970: $0 / 1000) }
            }
            applyRank(soloRank, to: existing)
            account = existing
        } else {
            account = LinkedAccount(
                riotGameName: gameName,
                riotTagline: tagLine,
                region: region.rawValue,
                platform: platform.rawValue,
                syncedGames: Array(gamesToSync)
            )
            account.profileIconID = summoner?.profileIconId
            account.summonerLevel = summoner?.summonerLevel
            account.lastRiotActivityDate = summoner?.revisionDate.map { Date(timeIntervalSince1970: $0 / 1000) }
            applyRank(soloRank, to: account)
            context.insert(account)
        }

        // Clear the Stage 1 mock matches now that real data is coming in.
        let existingMatches = try context.fetch(FetchDescriptor<Match>())
        for mockMatch in existingMatches where mockMatch.isMockData {
            context.delete(mockMatch)
        }

        // A rebuild drops stored matches so they get re-imported with every
        // field the current logic captures. Reflection notes are the one thing
        // the user authored themselves, so those are carried across by ID.
        var preservedNotes: [String: String] = [:]
        if rebuildExisting {
            for match in existingMatches where !match.isMockData {
                if !match.notes.isEmpty { preservedNotes[match.id] = match.notes }
                context.delete(match)
            }
        }

        var newMatchCount = 0

        if gamesToSync.contains(.league) {
            let knownIDs = rebuildExisting
                ? []
                : Set(existingMatches.filter { $0.game == .league && !$0.isMockData }.map(\.id))
            newMatchCount += try await syncLeague(client: client, puuid: puuid, region: region, knownIDs: knownIDs, context: context)
            account.lastLeagueSyncDate = .now
        }

        if gamesToSync.contains(.tft) {
            let knownIDs = Set(existingMatches.filter { $0.game == .tft && !$0.isMockData }.map(\.id))
            newMatchCount += try await syncTFT(client: client, puuid: puuid, region: region, knownIDs: knownIDs, context: context)
            account.lastTFTSyncDate = .now
        }

        // Restore the user's own reflection notes onto the rebuilt matches.
        if !preservedNotes.isEmpty,
           let rebuilt = try? context.fetch(FetchDescriptor<Match>()) {
            for match in rebuilt {
                if let note = preservedNotes[match.id] { match.notes = note }
            }
        }

        account.dataSchemaVersion = currentDataVersion
        // Record which key produced these PUUIDs so a key swap forces a rebuild.
        storedKeyFingerprint = currentKeyFingerprint

        try context.save()

        // The newest match is the one the reminder should open.
        var newestDescriptor = FetchDescriptor<Match>(sortBy: [SortDescriptor(\.timestamp, order: .reverse)])
        newestDescriptor.fetchLimit = 1
        let newest = (try? context.fetch(newestDescriptor))?.first
        NotificationService.scheduleReflectionReminder(
            newMatchCount: newMatchCount,
            matchID: newest?.id,
            championName: newest?.leagueStats?.champion
        )
        updateWidgetSnapshot(context: context)
    }

    private static func applyRank(_ entry: RiotLeagueEntry??, to account: LinkedAccount) {
        guard let entry = entry ?? nil else {
            account.rankTier = nil
            account.rankDivision = nil
            account.leaguePoints = nil
            account.rankWins = nil
            account.rankLosses = nil
            return
        }
        account.rankTier = entry.tier
        account.rankDivision = entry.rank
        account.leaguePoints = entry.leaguePoints
        account.rankWins = entry.wins
        account.rankLosses = entry.losses
    }

    private static func updateWidgetSnapshot(context: ModelContext) {
        var descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.leagueStats != nil },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let latest = try? context.fetch(descriptor).first, let stats = latest.leagueStats else { return }

        WidgetSnapshotWriter.write(
            LatestMatchSnapshot(
                champion: stats.champion,
                win: latest.win,
                kills: stats.kills,
                deaths: stats.deaths,
                assists: stats.assists,
                queueType: latest.queueType,
                timestamp: latest.timestamp
            )
        )
    }

    /// Prefix that keeps a browsed copy of a match from colliding with the
    /// player's own copy of the same game — `Match.id` is `@Attribute(.unique)`,
    /// so two rows sharing a Riot match id is not merely untidy, it is invalid.
    static func browsedID(for matchID: String) -> String { "browsed:\(matchID)" }

    /// Builds a browsable copy of another player's match, so their history can
    /// be opened the same way the player's own is.
    ///
    /// Deliberately separate from `syncLeague`'s import rather than refactored
    /// out of it. That path is the one thing in the app that must not break,
    /// and a browsed match genuinely differs: it is a cache, it is keyed so it
    /// can never collide with real history, nobody in it is the linked player,
    /// and it skips the timeline call — the gold chart and head-to-head table
    /// already degrade gracefully when that data is absent.
    @MainActor
    static func browsedMatch(
        detail: RiotMatchResponse,
        viewedPuuid: String,
        context: ModelContext
    ) -> Match? {
        let id = browsedID(for: detail.metadata.matchId)

        var descriptor = FetchDescriptor<Match>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let cached = try? context.fetch(descriptor).first { return cached }

        guard let viewed = detail.info.participants.first(where: { $0.puuid == viewedPuuid }) else {
            return nil
        }

        let match = Match(
            id: id,
            game: .league,
            win: viewed.win,
            queueType: queueTypeName(for: detail.info.queueId),
            gameDurationSeconds: detail.info.gameDuration,
            timestamp: Date(timeIntervalSince1970: Double(detail.info.gameCreation) / 1000)
        )
        match.queueId = detail.info.queueId
        match.isOwnHistory = false
        // The performance card belongs to whoever's profile we arrived from.
        match.leagueStats = LeagueStats(
            champion: viewed.championName,
            role: roleName(for: viewed.teamPosition),
            kills: viewed.kills,
            deaths: viewed.deaths,
            assists: viewed.assists,
            creepScore: viewed.totalMinionsKilled + viewed.neutralMinionsKilled,
            items: viewed.items,
            summonerSpellIDs: [viewed.summoner1Id, viewed.summoner2Id],
            goldEarned: viewed.goldEarned,
            damageDealtToChampions: viewed.totalDamageDealtToChampions,
            damageTaken: viewed.totalDamageTaken,
            visionScore: viewed.visionScore,
            wardsPlaced: viewed.wardsPlaced,
            keystoneID: viewed.perks.keystoneID,
            primaryStyleID: viewed.perks.primaryStyleID,
            subStyleID: viewed.perks.subStyleID,
            largestKillingSpree: viewed.largestKillingSpree ?? 0,
            wardsKilled: viewed.wardsKilled ?? 0
        )
        context.insert(match)

        for other in detail.info.participants {
            let summary = MatchParticipantSummary(
                puuid: other.puuid,
                riotIdGameName: other.riotIdGameName,
                riotIdTagline: other.riotIdTagline,
                teamId: other.teamId,
                champion: other.championName,
                role: roleName(for: other.teamPosition),
                kills: other.kills,
                deaths: other.deaths,
                assists: other.assists,
                win: other.win,
                items: other.items,
                goldEarned: other.goldEarned,
                damageDealtToChampions: other.totalDamageDealtToChampions,
                damageTaken: other.totalDamageTaken,
                totalHeal: other.totalHeal,
                creepScore: other.totalMinionsKilled + other.neutralMinionsKilled,
                visionScore: other.visionScore,
                wardsPlaced: other.wardsPlaced,
                wardsKilled: other.wardsKilled ?? 0,
                largestMultiKill: other.largestMultiKill ?? 0,
                largestKillingSpree: other.largestKillingSpree ?? 0,
                turretKills: other.turretKills ?? 0,
                summonerSpellIDs: [other.summoner1Id, other.summoner2Id],
                keystoneID: other.perks.keystoneID,
                primaryRuneIDs: other.perks.primaryRuneIDs,
                secondaryRuneIDs: other.perks.secondaryRuneIDs,
                primaryStyleID: other.perks.primaryStyleID,
                subStyleID: other.perks.subStyleID,
                statPerkIDs: other.perks.statPerkIDs,
                champLevel: other.champLevel ?? 0,
                augmentIDs: other.augmentIDs,
                // Nobody is "you" in someone else's game, even if you were in
                // it — the YOU badge means "this row is the account you linked",
                // and this screen was reached from a different player.
                isLinkedPlayer: false
            )
            summary.match = match
            context.insert(summary)
        }

        for team in detail.info.teams {
            let teamStats = TeamStats(
                teamId: team.teamId,
                win: team.win,
                baronKills: team.objectives.baron.kills,
                dragonKills: team.objectives.dragon.kills,
                towerKills: team.objectives.tower.kills,
                inhibitorKills: team.objectives.inhibitor.kills,
                heraldKills: team.objectives.riftHerald.kills,
                voidgrubKills: team.objectives.horde?.kills ?? 0
            )
            teamStats.match = match
            context.insert(teamStats)
        }

        try? context.save()
        return match
    }

    private static func syncLeague(
        client: RiotAPIClient,
        puuid: String,
        region: RiotRegion,
        knownIDs: Set<String>,
        context: ModelContext
    ) async throws -> Int {
        let matchIDs = try await client.fetchAllMatchIDs(puuid: puuid, region: region)
        var insertedCount = 0

        for matchID in matchIDs where !knownIDs.contains(matchID) {
            let detail: RiotMatchResponse
            do {
                detail = try await client.fetchMatch(matchID: matchID, region: region)
            } catch RiotAPIError.rateLimited {
                break // keep whatever we already imported this sync; try the rest next time
            } catch {
                continue // one bad match shouldn't sink the whole sync
            }
            guard let participant = detail.info.participants.first(where: { $0.puuid == puuid }) else { continue }

            let match = Match(
                id: detail.metadata.matchId,
                game: .league,
                win: participant.win,
                queueType: queueTypeName(for: detail.info.queueId),
                gameDurationSeconds: detail.info.gameDuration,
                timestamp: Date(timeIntervalSince1970: Double(detail.info.gameCreation) / 1000)
            )
            match.queueId = detail.info.queueId
            match.leagueStats = LeagueStats(
                champion: participant.championName,
                role: roleName(for: participant.teamPosition),
                kills: participant.kills,
                deaths: participant.deaths,
                assists: participant.assists,
                creepScore: participant.totalMinionsKilled + participant.neutralMinionsKilled,
                items: participant.items,
                summonerSpellIDs: [participant.summoner1Id, participant.summoner2Id],
                goldEarned: participant.goldEarned,
                damageDealtToChampions: participant.totalDamageDealtToChampions,
                damageTaken: participant.totalDamageTaken,
                visionScore: participant.visionScore,
                wardsPlaced: participant.wardsPlaced,
                keystoneID: participant.perks.keystoneID,
                primaryStyleID: participant.perks.primaryStyleID,
                subStyleID: participant.perks.subStyleID,
                doubleKills: participant.doubleKills,
                tripleKills: participant.tripleKills,
                quadraKills: participant.quadraKills,
                pentaKills: participant.pentaKills,
                turretKills: participant.turretKills ?? 0,
                inhibitorKills: participant.inhibitorKills ?? 0,
                dragonKills: participant.dragonKills ?? 0,
                baronKills: participant.baronKills ?? 0,
                objectivesStolen: participant.objectivesStolen ?? 0,
                firstBloodKill: participant.firstBloodKill ?? false,
                largestKillingSpree: participant.largestKillingSpree ?? 0,
                wardsKilled: participant.wardsKilled ?? 0
            )
            context.insert(match)

            for other in detail.info.participants {
                let summary = MatchParticipantSummary(
                    puuid: other.puuid,
                    riotIdGameName: other.riotIdGameName,
                    riotIdTagline: other.riotIdTagline,
                    teamId: other.teamId,
                    champion: other.championName,
                    role: roleName(for: other.teamPosition),
                    kills: other.kills,
                    deaths: other.deaths,
                    assists: other.assists,
                    win: other.win,
                    items: other.items,
                    goldEarned: other.goldEarned,
                    damageDealtToChampions: other.totalDamageDealtToChampions,
                    damageTaken: other.totalDamageTaken,
                    totalHeal: other.totalHeal,
                    creepScore: other.totalMinionsKilled + other.neutralMinionsKilled,
                    visionScore: other.visionScore,
                    wardsPlaced: other.wardsPlaced,
                    wardsKilled: other.wardsKilled ?? 0,
                    largestMultiKill: other.largestMultiKill ?? 0,
                    largestKillingSpree: other.largestKillingSpree ?? 0,
                    turretKills: other.turretKills ?? 0,
                    summonerSpellIDs: [other.summoner1Id, other.summoner2Id],
                    keystoneID: other.perks.keystoneID,
                    primaryRuneIDs: other.perks.primaryRuneIDs,
                    secondaryRuneIDs: other.perks.secondaryRuneIDs,
                    primaryStyleID: other.perks.primaryStyleID,
                    subStyleID: other.perks.subStyleID,
                    statPerkIDs: other.perks.statPerkIDs,
                    champLevel: other.champLevel ?? 0,
                    augmentIDs: other.augmentIDs,
                    isLinkedPlayer: other.puuid == puuid
                )
                summary.match = match
                context.insert(summary)
            }

            for team in detail.info.teams {
                let teamStats = TeamStats(
                    teamId: team.teamId,
                    win: team.win,
                    baronKills: team.objectives.baron.kills,
                    dragonKills: team.objectives.dragon.kills,
                    towerKills: team.objectives.tower.kills,
                    inhibitorKills: team.objectives.inhibitor.kills,
                    heraldKills: team.objectives.riftHerald.kills,
                    voidgrubKills: team.objectives.horde?.kills ?? 0
                )
                teamStats.match = match
                context.insert(teamStats)
            }

            var teamIDsByParticipantID: [Int: Int] = [:]
            for (index, other) in detail.info.participants.enumerated() {
                teamIDsByParticipantID[index + 1] = other.teamId
            }

            await importHeadToHead(
                client: client,
                matchID: matchID,
                region: region,
                participantPUUIDsInOrder: detail.info.participants.map(\.puuid),
                teamIDsByParticipantID: teamIDsByParticipantID,
                linkedPUUID: puuid,
                match: match,
                context: context
            )

            insertedCount += 1
        }

        return insertedCount
    }

    /// Reconstructs "who killed whom" between the linked player and each
    /// opponent from the match timeline. Best-effort: a missing or failed
    /// timeline just means the matchup table falls back to aggregate stats,
    /// so this never propagates an error into the wider sync.
    private static func importHeadToHead(
        client: RiotAPIClient,
        matchID: String,
        region: RiotRegion,
        participantPUUIDsInOrder: [String],
        teamIDsByParticipantID: [Int: Int],
        linkedPUUID: String,
        match: Match,
        context: ModelContext
    ) async {
        guard
            let timeline = try? await client.fetchMatchTimeline(matchID: matchID, region: region),
            let linkedIndex = participantPUUIDsInOrder.firstIndex(of: linkedPUUID)
        else { return }

        // Timeline participantIds are 1-based indices into info.participants.
        let linkedParticipantID = linkedIndex + 1
        var killsOn: [Int: Int] = [:]
        var deathsTo: [Int: Int] = [:]
        var assistsOn: [Int: Int] = [:]
        var soloKills = 0
        var dragonsByType: [String: Int] = [:]
        var heraldKills = 0
        var voidgrubKills = 0

        for frame in timeline.info.frames {
            for event in frame.events {
                switch event.type {
                case "CHAMPION_KILL":
                    if event.killerId == linkedParticipantID, let victim = event.victimId {
                        killsOn[victim, default: 0] += 1
                        // No assisting teammate credited means it was a 1v1.
                        if event.assistingParticipantIds?.isEmpty ?? true { soloKills += 1 }
                    }
                    // killerId 0 means an execution/turret kill with no player credited.
                    if event.victimId == linkedParticipantID, let killer = event.killerId, killer != 0 {
                        deathsTo[killer, default: 0] += 1
                    }
                    if event.assistingParticipantIds?.contains(linkedParticipantID) == true, let victim = event.victimId {
                        assistsOn[victim, default: 0] += 1
                    }

                case "ELITE_MONSTER_KILL" where event.killerId == linkedParticipantID:
                    switch event.monsterType {
                    case "DRAGON":
                        dragonsByType[event.monsterSubType ?? "UNKNOWN_DRAGON", default: 0] += 1
                    case "RIFTHERALD":
                        heraldKills += 1
                    case "HORDE":
                        voidgrubKills += 1
                    default:
                        break
                    }

                default:
                    break
                }
            }
        }

        if let stats = match.leagueStats {
            stats.soloKills = soloKills
            stats.dragonKillsByType = dragonsByType
            stats.riftHeraldKills = heraldKills
            stats.voidgrubKills = voidgrubKills
        }

        for (index, opponentPUUID) in participantPUUIDsInOrder.enumerated() where opponentPUUID != linkedPUUID {
            let participantID = index + 1
            let encounter = OpponentEncounter(
                opponentPuuid: opponentPUUID,
                killsOnOpponent: killsOn[participantID] ?? 0,
                deathsToOpponent: deathsTo[participantID] ?? 0,
                assistsOnOpponent: assistsOn[participantID] ?? 0
            )
            encounter.match = match
            context.insert(encounter)
        }

        importGoldCurve(
            timeline: timeline,
            linkedParticipantID: linkedParticipantID,
            teamIDs: teamIDsByParticipantID,
            match: match,
            context: context
        )
    }

    /// Turns each timeline frame's per-participant gold/XP snapshot into a
    /// per-minute team total, which is what a gold-difference graph needs.
    private static func importGoldCurve(
        timeline: RiotMatchTimelineResponse,
        linkedParticipantID: Int,
        teamIDs: [Int: Int],
        match: Match,
        context: ModelContext
    ) {
        guard let linkedTeamID = teamIDs[linkedParticipantID] else { return }

        for frame in timeline.info.frames {
            guard let frames = frame.participantFrames, !frames.isEmpty else { continue }
            let minute = (frame.timestamp ?? 0) / 60_000

            var allyGold = 0, enemyGold = 0, allyXP = 0, enemyXP = 0
            for participantFrame in frames.values {
                let isAlly = teamIDs[participantFrame.participantId] == linkedTeamID
                if isAlly {
                    allyGold += participantFrame.totalGold
                    allyXP += participantFrame.xp
                } else {
                    enemyGold += participantFrame.totalGold
                    enemyXP += participantFrame.xp
                }
            }

            let point = GoldTimelinePoint(
                minute: minute,
                allyGold: allyGold,
                enemyGold: enemyGold,
                allyXP: allyXP,
                enemyXP: enemyXP
            )
            point.match = match
            context.insert(point)
        }
    }

    private static func syncTFT(
        client: RiotAPIClient,
        puuid: String,
        region: RiotRegion,
        knownIDs: Set<String>,
        context: ModelContext
    ) async throws -> Int {
        let matchIDs = try await client.fetchRecentTFTMatchIDs(puuid: puuid, region: region)
        var insertedCount = 0

        for matchID in matchIDs where !knownIDs.contains(matchID) {
            let detail: RiotTFTMatchResponse
            do {
                detail = try await client.fetchTFTMatch(matchID: matchID, region: region)
            } catch RiotAPIError.rateLimited {
                break
            } catch {
                continue
            }
            guard let participant = detail.info.participants.first(where: { $0.puuid == puuid }) else { continue }

            let match = Match(
                id: detail.metadata.matchId,
                game: .tft,
                win: participant.placement <= 4,
                queueType: tftQueueTypeName(for: detail.info.queueId),
                gameDurationSeconds: Int(detail.info.gameLength.rounded()),
                timestamp: Date(timeIntervalSince1970: Double(detail.info.gameDatetime) / 1000)
            )
            match.tftStats = TFTStats(
                placement: participant.placement,
                level: participant.level,
                traits: participant.traits.filter { $0.tierCurrent > 0 }.map(\.name),
                units: participant.units.map(\.characterId)
            )
            context.insert(match)
            insertedCount += 1
        }

        return insertedCount
    }

    /// Names taken from Riot's published queue list
    /// (static.developer.riotgames.com/docs/lol/queues.json) rather than
    /// guessed, so modes stop collapsing into a meaningless "Other".
    static func queueTypeName(for queueId: Int) -> String {
        switch queueId {
        // Summoner's Rift
        case 400: return "Normal (Draft)"
        case 420: return "Ranked Solo/Duo"
        case 430: return "Normal (Blind)"
        case 440: return "Ranked Flex"
        case 480: return "Swiftplay"
        case 490: return "Quickplay"
        case 700: return "Clash"
        case 870, 880, 890: return "Co-op vs. AI"
        case 900, 1900: return "URF"
        case 1020: return "One for All"
        case 1400: return "Ultimate Spellbook"
        case 2000, 2010, 2020: return "Tutorial"
        // Howling Abyss
        case 450: return "ARAM"
        case 720: return "ARAM Clash"
        case 2400: return "ARAM: Mayhem"
        // Other maps
        case 1300: return "Nexus Blitz"
        case 1700, 1710: return "Arena"
        case 1810, 1820, 1830, 1840: return "Swarm"
        case 2300: return "Brawl"
        default: return "Queue \(queueId)"
        }
    }

    /// True for modes that hand out augments instead of (or alongside) runes.
    static func usesAugments(queueId: Int) -> Bool {
        switch queueId {
        case 1700, 1710, 2300, 2400: return true
        default: return false
        }
    }

    private static func tftQueueTypeName(for queueId: Int) -> String {
        switch queueId {
        case 1100: return "Ranked TFT"
        case 1090: return "Normal TFT"
        case 1160: return "Hyper Roll"
        case 1130: return "Double Up"
        default: return "Other"
        }
    }

    private static func roleName(for teamPosition: String) -> String {
        switch teamPosition {
        case "TOP": return "Top"
        case "JUNGLE": return "Jungle"
        case "MIDDLE": return "Mid"
        case "BOTTOM": return "ADC"
        case "UTILITY": return "Support"
        default: return "—"
        }
    }
}
