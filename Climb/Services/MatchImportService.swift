import Foundation
import SwiftData
import CryptoKit
import UserNotifications

enum MatchImportService {
    /// Bump when the import writes fields older records lack. Stale matches are rebuilt in place on
    /// the next sync: Riot rows are replaced, the `Match` row (notes, tags, coach chat) is kept.
    static let currentDataVersion = 10

    /// 20 matches plus their timelines fit one personal-key window (100 requests / 2 min).
    static let recentMatchCount = 20

    /// PUUIDs are encrypted per API key; another key's id fails with "Exception decrypting".
    /// So a key change marks every stored match stale; the next syncs rebuild them with fresh ids.
    private static let apiKeyFingerprintDefaultsKey = "riotAPIKeyFingerprint"

    private static var storedKeyFingerprint: String? {
        get { UserDefaults.standard.string(forKey: apiKeyFingerprintDefaultsKey) }
        set { UserDefaults.standard.set(newValue, forKey: apiKeyFingerprintDefaultsKey) }
    }

    /// Persists only a short SHA-256 digest, never the key (`hashValue` is seeded per process).
    private static var currentKeyFingerprint: String {
        let digest = SHA256.hash(data: Data(APIKeys.riot.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    static var apiKeyChangedSinceLastImport: Bool {
        storedKeyFingerprint != currentKeyFingerprint
    }

    /// Games Riot lists but won't serve; skipped this session so "load older" doesn't retry them.
    private static var unavailableIDs: Set<String> = []

    private static var lastImport: Task<Void, Never>?

    /// About ten profiles' worth of other players' games.
    static let browsedCacheLimit = 150

    /// A cache of other players' games: keep the newest `browsedCacheLimit`, and drop copies whose
    /// viewer isn't in their scoreboard (old id scheme, unfindable). Saved games are skipped.
    /// ponytail: newest by game date, not last opened, so an inactive friend is re-fetched; track a
    /// last-viewed date if that costs requests.
    private static func pruneBrowsedCopies(context: ModelContext) {
        let descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { !$0.isOwnHistory && !$0.isSaved },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let browsed = try? context.fetch(descriptor) else { return }
        for (index, match) in browsed.enumerated() where index >= browsedCacheLimit || match.focusParticipant == nil {
            context.delete(match)
        }
        try? context.save()
    }

    /// Runs imports one at a time, in call order: launch, refreshes, the account sheet and "load
    /// older" can fire together; overlapping imports each insert a scoreboard, doubling totals.
    private static func serialized<T: Sendable>(_ work: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = lastImport
        let task = Task { @MainActor in
            await previous?.value
            return try await work()
        }
        lastImport = Task { _ = await task.result }
        return try await task.value
    }

    /// Syncs on launch if a match is stale or the last sync is over ten minutes old.
    static func refreshIfNeeded(context: ModelContext) async {
        pruneBrowsedCopies(context: context)
        guard let account = try? context.fetch(FetchDescriptor<LinkedAccount>()).first else { return }

        let current = currentDataVersion
        var stale = FetchDescriptor<Match>(predicate: #Predicate {
            $0.isOwnHistory && $0.leagueStats != nil && $0.importVersion < current
        })
        stale.fetchLimit = 1
        let hasStale = account.syncedGames.contains(.league) && ((try? context.fetchCount(stale)) ?? 0) > 0
        let lastSync = max(account.lastLeagueSyncDate ?? .distantPast, account.lastTFTSyncDate ?? .distantPast)
        let isOld = lastSync < .now.addingTimeInterval(-10 * 60)
        guard hasStale || isOld || apiKeyChangedSinceLastImport else { return }
        try? await syncLinkedAccount(context: context)
    }

    /// Pull-to-refresh: re-syncs the linked account (no-op if none). The account is read when this
    /// sync's turn: read earlier, a refresh queued behind a logout would link it straight back.
    static func syncLinkedAccount(context: ModelContext) async throws {
        try await serialized {
            guard let account = try context.fetch(FetchDescriptor<LinkedAccount>()).first,
                  let platform = RiotPlatform(rawValue: account.platform)
            else { return }
            try await performSync(
                gameName: account.riotGameName,
                tagLine: account.riotTagline,
                platform: platform,
                gamesToSync: Set(account.syncedGames),
                context: context
            )
        }
    }

    static func linkAndSync(
        gameName: String,
        tagLine: String,
        platform: RiotPlatform,
        gamesToSync: Set<Game>,
        context: ModelContext
    ) async throws {
        try await serialized {
            try await performSync(
                gameName: gameName,
                tagLine: tagLine,
                platform: platform,
                gamesToSync: gamesToSync,
                context: context
            )
        }
    }

    /// "Load older": imports the next games below what's stored; returns the number added.
    @discardableResult
    static func loadOlderMatches(context: ModelContext) async throws -> Int {
        try await serialized {
            guard let account = try context.fetch(FetchDescriptor<LinkedAccount>()).first,
                  let platform = RiotPlatform(rawValue: account.platform)
            else { return 0 }
            let region = platform.region
            let client = RiotAPIClient.shared
            let puuid = try await client.resolvePUUID(gameName: account.riotGameName, tagLine: account.riotTagline, region: region)
            let known = Set(try context.fetch(FetchDescriptor<Match>(predicate: #Predicate { $0.isOwnHistory })).map(\.id))

            // Walk Riot's list from the top for unstored games: an offset by the stored count would
            // skip gaps (20+ games between syncs, another account's matches). 100 IDs per request.
            var newIDs: [String] = []
            var start = 0
            while newIDs.count < recentMatchCount {
                let page = try await client.fetchRecentMatchIDs(puuid: puuid, region: region, start: start, count: 100)
                newIDs += page.filter { !known.contains($0) && !unavailableIDs.contains($0) }
                if page.count < 100 { break }
                start += 100
            }

            var added = 0
            var hitRateLimit = false
            for matchID in newIDs.prefix(recentMatchCount) {
                let complete: Bool
                do {
                    complete = try await importLeagueMatch(matchID, into: nil, client: client, puuid: puuid, region: region, context: context)
                } catch RiotAPIError.rateLimited, RiotAPIError.network {
                    hitRateLimit = true
                    break
                } catch RiotAPIError.unauthorized {
                    throw RiotAPIError.unauthorized
                } catch {
                    unavailableIDs.insert(matchID)
                    continue
                }
                added += 1
                if !complete { break }
            }
            try context.save()
            // Nothing added because of the limit is not "no older games".
            if added == 0, hitRateLimit { throw RiotAPIError.rateLimited }
            return added
        }
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
        APIKeyPrompt.shared.riotKeyRejected = false
        let summoner = try? await client.fetchSummoner(puuid: puuid, platform: platform)
        let leagueEntries = try? await client.fetchLeagueEntries(puuid: puuid, platform: platform)

        try dropOtherAccountsHistory(gameName: gameName, tagLine: tagLine, puuid: puuid, context: context)

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
            // Recorded now, so a rate-limited rebuild doesn't re-mark everything stale every sync.
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

    /// Linking a different account starts clean (games, rank, widget) before the import, so a
    /// failed sync can't leave old games under the new name. A new Riot ID is a switch unless a
    /// game imported under the current key has the new puuid (a rename); puuids change per key.
    /// ponytail: a rename right after a key change (no comparable games yet) reads as a switch;
    /// store the account's puuid per key if that matters.
    private static func dropOtherAccountsHistory(gameName: String, tagLine: String, puuid: String, context: ModelContext) throws {
        let existing = try context.fetch(FetchDescriptor<LinkedAccount>()).first
        let own = try context.fetch(FetchDescriptor<Match>(predicate: #Predicate { $0.isOwnHistory }))
        let current = currentDataVersion
        let comparable = apiKeyChangedSinceLastImport ? [] : own.filter { $0.importVersion == current }
        let nameChanged = existing.map {
            LinkedAccount.identity(gameName: $0.riotGameName, tagLine: $0.riotTagline)
                != LinkedAccount.identity(gameName: gameName, tagLine: tagLine)
        } ?? false
        let switched = nameChanged && !comparable.contains { $0.focusParticipant?.puuid == puuid }

        let foreign = switched ? own : comparable.filter { match in
            match.focusParticipant.map { $0.puuid != puuid } ?? false
        }
        removeFromHistory(foreign, context: context)

        if switched, let existing {
            // Reset in place, not deleted: an empty account list would show onboarding mid-sync.
            existing.profileIconID = nil
            existing.summonerLevel = nil
            existing.lastLeagueSyncDate = nil
            existing.lastTFTSyncDate = nil
            existing.lastRiotActivityDate = nil
            applyRank(nil, to: existing)
        }
        guard switched || !foreign.isEmpty else { return }
        clearAccountCaches()
        try context.save()
    }

    /// Unlinks the account; games leave as in a switch. API keys and followed players stay: they
    /// belong to the device, not the Riot account.
    static func logOut(context: ModelContext) async throws {
        // Queued behind any running sync, which would write the account back.
        try await serialized {
            removeFromHistory(try context.fetch(FetchDescriptor<Match>(predicate: #Predicate { $0.isOwnHistory })), context: context)
            for account in try context.fetch(FetchDescriptor<LinkedAccount>()) { context.delete(account) }
            clearAccountCaches()
            try context.save()
        }
    }

    private static func clearAccountCaches() {
        UNUserNotificationCenter.current().removeAllPendingNotificationRequests()
        WidgetSnapshotWriter.clear()
        UserDefaults.standard.removeObject(forKey: "trendDiagnosis")
        UserDefaults.standard.removeObject(forKey: "trendDiagnosisKey")
    }

    /// Drops games from the history (logout, switch); a saved game stays, under Saved Games only.
    private static func removeFromHistory(_ matches: [Match], context: ModelContext) {
        for match in matches {
            if match.isSaved { match.isOwnHistory = false } else { context.delete(match) }
        }
    }

    /// Puts a game `removeFromHistory` kept back into the history. Reused, never re-inserted:
    /// `Match.id` is unique, and a second copy would double its scoreboard.
    private static func reclaimKeptMatch(id: String, context: ModelContext) -> Match? {
        var descriptor = FetchDescriptor<Match>(predicate: #Predicate { $0.id == id && !$0.isOwnHistory })
        descriptor.fetchLimit = 1
        guard let kept = try? context.fetch(descriptor).first else { return nil }
        kept.isOwnHistory = true
        return kept
    }

    #if DEBUG
    /// Runs at launch in debug builds, on a throwaway in-memory store.
    static func selfCheck() {
        let container = try! ModelContainer(for: Match.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true))
        let context = container.mainContext
        for (id, own, saved) in [("JP1_1", true, true), ("JP1_2", true, false),
                                 ("browsed:p:JP1_3", false, true), ("browsed:p:JP1_4", false, false)] {
            let match = newMatch(id: id, game: .league)
            match.isOwnHistory = own
            match.isSaved = saved
            context.insert(match)
        }
        var failures: [String] = []
        func ids() -> Set<String> { Set(((try? context.fetch(FetchDescriptor<Match>())) ?? []).map(\.id)) }
        removeFromHistory(try! context.fetch(FetchDescriptor<Match>(predicate: #Predicate { $0.isOwnHistory })), context: context)
        try? context.save()
        if ids().contains("JP1_2") { failures.append("logging out deletes an unsaved game") }
        // No copy has its viewer in a scoreboard, which drops an unsaved one.
        pruneBrowsedCopies(context: context)

        let left = try! context.fetch(FetchDescriptor<Match>())
        if ids() != ["JP1_1", "browsed:p:JP1_3"] {
            failures.append("only saved games outlive logout and the cache cap, got \(ids().sorted())")
        }
        if left.first(where: { $0.id == "JP1_1" })?.isOwnHistory != false {
            failures.append("a kept game leaves the history")
        }
        if reclaimKeptMatch(id: "JP1_1", context: context)?.isOwnHistory != true {
            failures.append("its account syncing again takes a kept game back")
        }
        assert(failures.isEmpty, failures.joined(separator: "; "))
    }
    #endif

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

    /// Imports the recent page, then rebuilds stale stored matches newest first. Stops at the first
    /// rate limit; whatever is left stays stale for the next sync.
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
            } catch RiotAPIError.rateLimited, RiotAPIError.network {
                break
            } catch RiotAPIError.unexpectedStatus(500...) {
                continue // Riot hiccup — stays stale, retried next sync
            } catch RiotAPIError.unauthorized {
                // Key expired mid-sync: stop, don't write the rest off as unavailable.
                throw RiotAPIError.unauthorized
            } catch {
                // Never served (gone or undecodable): stop retrying it every launch; old rows stay.
                existing?.importVersion = currentDataVersion
                continue
            }
            if existing == nil { insertedCount += 1 }
            if !complete { break } // the timeline hit the rate limit; the rest can wait
        }
        return insertedCount
    }

    /// Returns false when the timeline failed transiently: the match is saved but left stale, so a
    /// later sync fills in the gold curve and head-to-head.
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
        } catch RiotAPIError.rateLimited, RiotAPIError.network, RiotAPIError.unexpectedStatus(500...) {
            complete = false
        } catch RiotAPIError.unauthorized {
            throw RiotAPIError.unauthorized
        } catch {
            // No timeline for this game (old, or a mode without one); a retry changes nothing.
        }

        let reused = existing ?? reclaimKeptMatch(id: matchID, context: context)
        let match = reused ?? newMatch(id: matchID, game: .league)
        if reused == nil { context.insert(match) }
        // A review written without the timeline never saw the gold curve or head-to-head: redo it.
        if timeline != nil, reused?.goldTimeline.isEmpty == true { match.reviewText = nil }
        populate(match, from: detail, focus: puuid, linkedPUUID: puuid, timeline: timeline, context: context)
        match.importVersion = complete ? currentDataVersion : 0
        return complete
    }

    /// Keeps a browsed copy from colliding with the player's own copy (`Match.id` is unique) or
    /// another viewer's: the performance card belongs to whoever's profile it was opened from.
    /// ponytail: the viewer's puuid changes with the daily API key, so a saved copy isn't found
    /// after rotation and saving the fresh copy gives Saved Games two. Re-key saved copies here.
    static func browsedID(for matchID: String, viewer: String) -> String {
        "browsed:\(viewer):\(matchID)"
    }

    /// Another player's game as a cached `Match` with the same rows as your own. It skips the
    /// timeline call, so there's no gold chart or head-to-head.
    static func browsedMatch(
        matchID: String,
        viewedPuuid: String,
        region: RiotRegion,
        context: ModelContext
    ) async throws -> Match? {
        let id = browsedID(for: matchID, viewer: viewedPuuid)
        var descriptor = FetchDescriptor<Match>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        if let cached = try? context.fetch(descriptor).first, cached.importVersion == currentDataVersion {
            return cached
        }
        let detail = try await RiotAPIClient.shared.fetchMatch(matchID: matchID, region: region)
        // Read again: another load may have cached it during the request.
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

    /// The one place a scoreboard is built (own history and browsed games), replacing earlier rows.
    /// `focus` is whose performance card it is; `linkedPUUID` is nil if browsing (nobody is "you").
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
            let stats = LeagueStats(player, role: roleName(for: player.teamPosition))
            context.insert(stats)
            match.leagueStats = stats
        }

        for participant in info.participants {
            let summary = MatchParticipantSummary(
                participant,
                role: roleName(for: participant.teamPosition),
                isLinkedPlayer: participant.puuid == linkedPUUID
            )
            context.insert(summary)
            summary.match = match
        }

        for team in info.teams {
            let teamStats = TeamStats(team)
            context.insert(teamStats)
            teamStats.match = match
        }

        if let timeline, let linkedPUUID {
            importHeadToHead(timeline: timeline, participants: info.participants, linkedPUUID: linkedPUUID, match: match, context: context)
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

    /// Rebuilds per-opponent kills, deaths and assists plus objective credit from timeline events.
    private static func importHeadToHead(
        timeline: RiotMatchTimelineResponse,
        participants: [RiotMatchResponse.Participant],
        linkedPUUID: String,
        match: Match,
        context: ModelContext
    ) {
        guard let linkedIndex = participants.firstIndex(where: { $0.puuid == linkedPUUID }) else { return }

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

        for (index, opponent) in participants.enumerated() where opponent.puuid != linkedPUUID {
            let participantID = index + 1
            let encounter = OpponentEncounter(
                opponentPuuid: opponent.puuid,
                killsOnOpponent: killsOn[participantID] ?? 0,
                deathsToOpponent: deathsTo[participantID] ?? 0,
                assistsOnOpponent: assistsOn[participantID] ?? 0
            )
            context.insert(encounter)
            encounter.match = match
        }

        importGoldCurve(timeline: timeline, participants: participants, linkedParticipantID: linkedParticipantID, match: match, context: context)
    }

    /// Sums each frame's gold/XP into per-minute ally and enemy totals for the gold graph.
    private static func importGoldCurve(
        timeline: RiotMatchTimelineResponse,
        participants: [RiotMatchResponse.Participant],
        linkedParticipantID: Int,
        match: Match,
        context: ModelContext
    ) {
        let teamIDs = Dictionary(uniqueKeysWithValues: participants.enumerated().map { ($0.offset + 1, $0.element.teamId) })
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
        // Best-effort: likeliest to 429 after a League rebuild; TFT can catch up next sync.
        guard let matchIDs = try? await client.fetchRecentTFTMatchIDs(puuid: puuid, region: region, count: recentMatchCount) else { return 0 }
        var insertedCount = 0

        for matchID in matchIDs where !knownIDs.contains(matchID) {
            if reclaimKeptMatch(id: matchID, context: context) != nil { continue }
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

    /// From Riot's published queue list: static.developer.riotgames.com/docs/lol/queues.json
    static func queueTypeName(for queueId: Int) -> String {
        switch queueId {
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
        case 450: return "ARAM"
        case 720: return "ARAM Clash"
        case 2400: return "ARAM: Mayhem"
        case 1300: return "Nexus Blitz"
        case 1700, 1710: return "Arena"
        case 1810, 1820, 1830, 1840: return "Swarm"
        case 2300: return "Brawl"
        default: return "Queue \(queueId)"
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
