import Foundation
import SwiftData
import CryptoKit

@MainActor
enum MatchImportService {
    /// Bump whenever the import writes fields older records don't have.
    ///
    /// Each match remembers the version that built it (`Match.importVersion`),
    /// and a stale match is rebuilt *in place* on the next sync: the Riot-derived
    /// rows under it are replaced, but the `Match` row itself — the player's
    /// notes, tags and coach conversation — is never deleted.
    /// v10: per-match versioning; the rebuild also clears the duplicate
    /// scoreboard rows that overlapping syncs used to insert.
    static let currentDataVersion = 10

    /// How many recent games a sync looks at. op.gg and 掌盟 both open on 20,
    /// and 20 matches plus their timelines fit inside one personal-key window
    /// (100 requests / 2 min).
    static let recentMatchCount = 20

    /// PUUIDs are encrypted per API key: Riot answers a lookup made with a
    /// different key than the one that issued the id with
    /// "Bad Request - Exception decrypting …". So a key change marks every
    /// stored match stale, and the next syncs rebuild them with fresh ids.
    private static let apiKeyFingerprintDefaultsKey = "riotAPIKeyFingerprint"

    private static var storedKeyFingerprint: String? {
        get { UserDefaults.standard.string(forKey: apiKeyFingerprintDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyFingerprintDefaultsKey) }
    }

    /// Only a short digest is persisted — never the key itself.
    ///
    /// SHA-256 rather than `Hasher`/`hashValue`: Swift seeds those randomly
    /// per process, so the same key would hash differently on every launch.
    private static var currentKeyFingerprint: String {
        let digest = SHA256.hash(data: Data(Secrets.riotAPIKey.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    static var apiKeyChangedSinceLastImport: Bool {
        storedKeyFingerprint != currentKeyFingerprint
    }

    /// The most recently started sync. Every new sync waits for it first.
    private static var lastSync: Task<Void, Error>?

    /// Syncs on launch when something is stale — an import-logic bump, a key
    /// change, or a timeline an earlier sync couldn't fetch — so the player
    /// never has to know a backfill exists.
    static func refreshIfNeeded(context: ModelContext) async {
        guard let account = try? context.fetch(FetchDescriptor<LinkedAccount>()).first else { return }

        let current = currentDataVersion
        var stale = FetchDescriptor<Match>(predicate: #Predicate {
            $0.isOwnHistory && $0.leagueStats != nil && $0.importVersion < current
        })
        stale.fetchLimit = 1
        let hasStale = account.syncedGames.contains(.league) && ((try? context.fetchCount(stale)) ?? 0) > 0
        guard hasStale || apiKeyChangedSinceLastImport else { return }
        try? await syncLinkedAccount(context: context)
    }

    /// Re-syncs the linked account with its stored Riot ID and game choices —
    /// what pull-to-refresh does. No account linked is a no-op.
    static func syncLinkedAccount(context: ModelContext) async throws {
        guard let account = try context.fetch(FetchDescriptor<LinkedAccount>()).first,
              let platform = RiotPlatform(rawValue: account.platform)
        else { return }
        try await linkAndSync(
            gameName: account.riotGameName,
            tagLine: account.riotTagline,
            platform: platform,
            gamesToSync: Set(account.syncedGames),
            context: context
        )
    }

    /// Runs syncs one at a time, in call order.
    ///
    /// Launch, both pull-to-refreshes and the account sheet can all fire at
    /// once. Two overlapping imports each inserted the same match's scoreboard,
    /// which doubled every team total and put a "19th" in a ten-player game.
    /// Chaining here protects every caller at once.
    static func linkAndSync(
        gameName: String,
        tagLine: String,
        platform: RiotPlatform,
        gamesToSync: Set<Game>,
        context: ModelContext
    ) async throws {
        let previous = lastSync
        let task = Task {
            _ = await previous?.result
            try await performSync(
                gameName: gameName,
                tagLine: tagLine,
                platform: platform,
                gamesToSync: gamesToSync,
                context: context
            )
        }
        lastSync = task
        try await task.value
    }

    private static func performSync(
        gameName: String,
        tagLine: String,
        platform: RiotPlatform,
        gamesToSync: Set<Game>,
        context: ModelContext
    ) async throws {
        let region = platform.region
        let client = RiotAPIClient.shared
        let puuid = try await client.resolvePUUID(gameName: gameName, tagLine: tagLine, region: region)
        let summoner = try? await client.fetchSummoner(puuid: puuid, platform: platform)
        let leagueEntries = try? await client.fetchLeagueEntries(puuid: puuid, platform: platform)

        let account: LinkedAccount
        if let existing = try context.fetch(FetchDescriptor<LinkedAccount>()).first {
            existing.riotGameName = gameName
            existing.riotTagline = tagLine
            existing.region = region.rawValue
            existing.platform = platform.rawValue
            existing.syncedGames = Array(gamesToSync)
            account = existing
        } else {
            account = LinkedAccount(
                riotGameName: gameName,
                riotTagline: tagLine,
                region: region.rawValue,
                platform: platform.rawValue,
                syncedGames: Array(gamesToSync)
            )
            context.insert(account)
        }
        if let summoner {
            account.profileIconID = summoner.profileIconId
            account.summonerLevel = summoner.summonerLevel
            account.lastRiotActivityDate = summoner.revisionDate.map { Date(timeIntervalSince1970: $0 / 1000) }
        }
        // Only when the call succeeded — a rate-limited lookup isn't "unranked".
        if let leagueEntries {
            applyRank(leagueEntries.first { $0.queueType == "RANKED_SOLO_5x5" }, to: account)
        }

        if apiKeyChangedSinceLastImport {
            // Browsed copies too: their scoreboards hold old-key ids as well.
            for match in try context.fetch(FetchDescriptor<Match>()) { match.importVersion = 0 }
            // Recorded now, not at the end: a rebuild that runs into the rate
            // limit must not re-mark everything stale on every later sync.
            storedKeyFingerprint = currentKeyFingerprint
            try context.save()
        }
        let ownMatches = try context.fetch(FetchDescriptor<Match>(predicate: #Predicate { $0.isOwnHistory }))

        var newMatchCount = 0

        if gamesToSync.contains(.league) {
            newMatchCount += try await syncLeague(
                client: client,
                puuid: puuid,
                region: region,
                stored: ownMatches.filter { $0.game == .league },
                context: context
            )
            account.lastLeagueSyncDate = .now
        }

        if gamesToSync.contains(.tft) {
            let knownIDs = Set(ownMatches.filter { $0.game == .tft }.map(\.id))
            newMatchCount += try await syncTFT(client: client, puuid: puuid, region: region, knownIDs: knownIDs, context: context)
            account.lastTFTSyncDate = .now
        }

        try context.save()

        // The newest match is the one the reminder should open.
        var newestDescriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.isOwnHistory },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        newestDescriptor.fetchLimit = 1
        let newest = (try? context.fetch(newestDescriptor))?.first
        NotificationService.scheduleReflectionReminder(
            newMatchCount: newMatchCount,
            matchID: newest?.id,
            championName: newest?.leagueStats?.champion
        )
        updateWidgetSnapshot(context: context)
    }

    private static func applyRank(_ entry: RiotLeagueEntry?, to account: LinkedAccount) {
        account.rankTier = entry?.tier
        account.rankDivision = entry?.rank
        account.leaguePoints = entry?.leaguePoints
        account.rankWins = entry?.wins
        account.rankLosses = entry?.losses
    }

    private static func updateWidgetSnapshot(context: ModelContext) {
        var descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { $0.isOwnHistory && $0.leagueStats != nil },
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

    // MARK: - League

    /// Imports the recent page, then rebuilds any stored match an older import
    /// left stale, newest first. Stops at the first rate limit; whatever is
    /// left stays stale and the next sync picks it up.
    private static func syncLeague(
        client: RiotAPIClient,
        puuid: String,
        region: RiotRegion,
        stored: [Match],
        context: ModelContext
    ) async throws -> Int {
        let byID = Dictionary(stored.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let recentIDs = try await client.fetchRecentMatchIDs(puuid: puuid, region: region, count: recentMatchCount)
        let needsImport = { (id: String) in (byID[id]?.importVersion ?? -1) < currentDataVersion }
        let staleOlderIDs = stored
            .filter { $0.importVersion < currentDataVersion && !recentIDs.contains($0.id) }
            .sorted { $0.timestamp > $1.timestamp }
            .map(\.id)

        var insertedCount = 0
        for matchID in recentIDs.filter(needsImport) + staleOlderIDs {
            let existing = byID[matchID]
            let complete: Bool
            do {
                complete = try await importLeagueMatch(matchID, into: existing, client: client, puuid: puuid, region: region, context: context)
            } catch RiotAPIError.rateLimited {
                break
            } catch RiotAPIError.network {
                break
            } catch RiotAPIError.unexpectedStatus(let code) where code >= 500 {
                continue // Riot hiccup — stays stale, retried next sync
            } catch {
                // Riot will never serve this match (gone, or undecodable), so
                // stop retrying it on every launch. Its old rows stay as they are.
                existing?.importVersion = currentDataVersion
                continue
            }
            if existing == nil { insertedCount += 1 }
            if !complete { break } // the timeline hit the rate limit; the rest can wait
        }
        return insertedCount
    }

    /// Returns false when the timeline failed for a transient reason. The
    /// match is still saved, but left stale so a later sync fills in the gold
    /// curve and head-to-head instead of losing them for good.
    private static func importLeagueMatch(
        _ matchID: String,
        into existing: Match?,
        client: RiotAPIClient,
        puuid: String,
        region: RiotRegion,
        context: ModelContext
    ) async throws -> Bool {
        let detail = try await client.fetchMatch(matchID: matchID, region: region)

        var timeline: RiotMatchTimelineResponse?
        var complete = true
        do {
            timeline = try await client.fetchMatchTimeline(matchID: matchID, region: region)
        } catch RiotAPIError.rateLimited {
            complete = false
        } catch RiotAPIError.network {
            complete = false
        } catch RiotAPIError.unexpectedStatus(let code) where code >= 500 {
            complete = false
        } catch {
            // No timeline exists for this game (old, or a mode without one) —
            // nothing a retry would change.
        }

        let match = existing ?? newMatch(id: matchID, game: .league)
        if existing == nil { context.insert(match) }
        populate(match, from: detail, focus: puuid, linkedPUUID: puuid, timeline: timeline, context: context)
        match.importVersion = complete ? currentDataVersion : 0
        return complete
    }

    /// Prefix that keeps a browsed copy of a match from colliding with the
    /// player's own copy of the same game — `Match.id` is `@Attribute(.unique)`.
    static func browsedID(for matchID: String) -> String { "browsed:\(matchID)" }

    /// A browsable copy of another player's match, so their history opens the
    /// same way the player's own does. It is a cache: keyed so it never
    /// collides with real history, nobody in it is "you", and it skips the
    /// timeline call — the gold chart and head-to-head degrade gracefully.
    static func browsedMatch(
        detail: RiotMatchResponse,
        viewedPuuid: String,
        context: ModelContext
    ) -> Match? {
        let id = browsedID(for: detail.metadata.matchId)
        var descriptor = FetchDescriptor<Match>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        let cached = try? context.fetch(descriptor).first
        if let cached, cached.importVersion == currentDataVersion { return cached }

        guard detail.info.participants.contains(where: { $0.puuid == viewedPuuid }) else { return nil }

        let match = cached ?? newMatch(id: id, game: .league)
        if cached == nil {
            match.isOwnHistory = false
            context.insert(match)
        }
        populate(match, from: detail, focus: viewedPuuid, linkedPUUID: nil, timeline: nil, context: context)
        match.importVersion = currentDataVersion
        try? context.save()
        return match
    }

    /// Placeholder values only — `populate` overwrites every one of them.
    private static func newMatch(id: String, game: Game) -> Match {
        Match(id: id, game: game, win: false, queueType: "", gameDurationSeconds: 0, timestamp: .now)
    }

    /// Writes everything Riot knows about one game onto `match`, replacing
    /// whatever an earlier import put there.
    ///
    /// The one place a scoreboard gets built, for the player's own history and
    /// for browsed games alike. `focus` is whose performance card this is;
    /// `linkedPUUID` is nil for a browsed game, since nobody in it is "you".
    private static func populate(
        _ match: Match,
        from detail: RiotMatchResponse,
        focus: String,
        linkedPUUID: String?,
        timeline: RiotMatchTimelineResponse?,
        context: ModelContext
    ) {
        clearDerivedData(of: match, context: context)

        let info = detail.info
        match.queueId = info.queueId
        match.queueType = queueTypeName(for: info.queueId)
        match.gameDurationSeconds = info.gameDuration
        match.timestamp = Date(timeIntervalSince1970: Double(info.gameCreation) / 1000)

        if let player = info.participants.first(where: { $0.puuid == focus }) {
            match.win = player.win
            let stats = leagueStats(for: player)
            context.insert(stats)
            match.leagueStats = stats
        }

        for participant in info.participants {
            let summary = participantSummary(for: participant, isLinkedPlayer: participant.puuid == linkedPUUID)
            context.insert(summary)
            summary.match = match
        }

        for team in info.teams {
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
            context.insert(teamStats)
            teamStats.match = match
        }

        if let timeline, let linkedPUUID {
            importHeadToHead(
                timeline: timeline,
                participantPUUIDsInOrder: info.participants.map(\.puuid),
                teamIDsByParticipantID: Dictionary(
                    uniqueKeysWithValues: info.participants.enumerated().map { ($0.offset + 1, $0.element.teamId) }
                ),
                linkedPUUID: linkedPUUID,
                match: match,
                context: context
            )
        }
    }

    private static func clearDerivedData(of match: Match, context: ModelContext) {
        if let stats = match.leagueStats { context.delete(stats) }
        for row in match.participants { context.delete(row) }
        for row in match.teamStats { context.delete(row) }
        for row in match.opponentEncounters { context.delete(row) }
        for row in match.goldTimeline { context.delete(row) }
        match.leagueStats = nil
        match.participants = []
        match.teamStats = []
        match.opponentEncounters = []
        match.goldTimeline = []
    }

    private static func leagueStats(for participant: RiotMatchResponse.Participant) -> LeagueStats {
        LeagueStats(
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
    }

    private static func participantSummary(
        for participant: RiotMatchResponse.Participant,
        isLinkedPlayer: Bool
    ) -> MatchParticipantSummary {
        MatchParticipantSummary(
            puuid: participant.puuid,
            riotIdGameName: participant.riotIdGameName,
            riotIdTagline: participant.riotIdTagline,
            teamId: participant.teamId,
            champion: participant.championName,
            role: roleName(for: participant.teamPosition),
            kills: participant.kills,
            deaths: participant.deaths,
            assists: participant.assists,
            win: participant.win,
            items: participant.items,
            goldEarned: participant.goldEarned,
            damageDealtToChampions: participant.totalDamageDealtToChampions,
            damageTaken: participant.totalDamageTaken,
            totalHeal: participant.totalHeal,
            creepScore: participant.totalMinionsKilled + participant.neutralMinionsKilled,
            visionScore: participant.visionScore,
            wardsPlaced: participant.wardsPlaced,
            wardsKilled: participant.wardsKilled ?? 0,
            largestMultiKill: participant.largestMultiKill ?? 0,
            largestKillingSpree: participant.largestKillingSpree ?? 0,
            turretKills: participant.turretKills ?? 0,
            summonerSpellIDs: [participant.summoner1Id, participant.summoner2Id],
            keystoneID: participant.perks.keystoneID,
            primaryRuneIDs: participant.perks.primaryRuneIDs,
            secondaryRuneIDs: participant.perks.secondaryRuneIDs,
            primaryStyleID: participant.perks.primaryStyleID,
            subStyleID: participant.perks.subStyleID,
            statPerkIDs: participant.perks.statPerkIDs,
            champLevel: participant.champLevel ?? 0,
            augmentIDs: participant.augmentIDs,
            isLinkedPlayer: isLinkedPlayer
        )
    }

    /// Reconstructs "who killed whom" between the linked player and each
    /// opponent from the match timeline, plus the objective credit that only
    /// timeline events carry.
    private static func importHeadToHead(
        timeline: RiotMatchTimelineResponse,
        participantPUUIDsInOrder: [String],
        teamIDsByParticipantID: [Int: Int],
        linkedPUUID: String,
        match: Match,
        context: ModelContext
    ) {
        guard let linkedIndex = participantPUUIDsInOrder.firstIndex(of: linkedPUUID) else { return }

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
            context.insert(encounter)
            encounter.match = match
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
            context.insert(point)
            point.match = match
        }
    }

    // MARK: - TFT

    private static func syncTFT(
        client: RiotAPIClient,
        puuid: String,
        region: RiotRegion,
        knownIDs: Set<String>,
        context: ModelContext
    ) async throws -> Int {
        // Best-effort: after a League rebuild has used up the rate limit, this
        // call is the likeliest to 429, and TFT can simply catch up next sync.
        guard let matchIDs = try? await client.fetchRecentTFTMatchIDs(puuid: puuid, region: region, count: recentMatchCount) else { return 0 }
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
            match.importVersion = currentDataVersion
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

    // MARK: - Names

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
