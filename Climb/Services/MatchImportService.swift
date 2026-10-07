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
        let digest = SHA256.hash(data: Data(APIKeys.riot.utf8))
        return digest.map { String(format: "%02x", $0) }.joined().prefix(16).description
    }

    static var apiKeyChangedSinceLastImport: Bool {
        storedKeyFingerprint != currentKeyFingerprint
    }

    /// Games Riot listed but won't serve (gone, or undecodable). Skipped for
    /// the rest of the session so "load older" doesn't retry them every tap.
    private static var unavailableIDs: Set<String> = []

    /// The most recently started import. Every new one waits for it first.
    private static var lastImport: Task<Void, Never>?

    /// How many of other players' games to keep. About ten profiles' worth.
    static let browsedCacheLimit = 150

    /// Other players' games are only a cache — reopening a profile fetches
    /// whatever is gone — so keep the newest `browsedCacheLimit`, and drop any
    /// copy whose viewer can't be found in it (an older id scheme), which can
    /// never be looked up again.
    ///
    /// ponytail: newest by game date, not by when it was last opened; a friend
    /// who hasn't played in a while gets re-fetched. Track a last-viewed date if
    /// that starts to cost requests.
    private static func pruneBrowsedCopies(context: ModelContext) {
        let descriptor = FetchDescriptor<Match>(
            predicate: #Predicate { !$0.isOwnHistory },
            sortBy: [SortDescriptor(\.timestamp, order: .reverse)]
        )
        guard let browsed = try? context.fetch(descriptor) else { return }
        for (index, match) in browsed.enumerated() where index >= browsedCacheLimit || match.focusParticipant == nil {
            context.delete(match)
        }
        try? context.save()
    }

    /// Runs imports one at a time, in call order.
    ///
    /// Launch, both pull-to-refreshes, the account sheet and "load older" can
    /// all fire at once. Two overlapping imports each inserted the same
    /// match's scoreboard, which doubled every team total and put a "19th" in
    /// a ten-player game. Chaining here protects every caller at once.
    private static func serialized<T: Sendable>(_ work: @escaping @MainActor () async throws -> T) async throws -> T {
        let previous = lastImport
        let task = Task { @MainActor in
            await previous?.value
            return try await work()
        }
        lastImport = Task { _ = await task.result }
        return try await task.value
    }

    /// Syncs on launch when something is stale — an import-logic bump, a key
    /// change, a timeline an earlier sync couldn't fetch — or the last sync is
    /// over ten minutes old, the way 掌盟 and op.gg refresh when opened.
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

    /// The next page of League history below what's stored — "load older" at
    /// the foot of the match list. Returns how many games it added; 0 means
    /// Riot has nothing older (or the rate limit stopped it first).
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

            // Walk Riot's list from the top and take the first games not yet
            // stored. Offsetting by the stored count would skip any gap — more
            // than 20 games between syncs, or another account's matches. IDs
            // are one request per hundred, so the walk itself is cheap.
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
                } catch RiotAPIError.rateLimited {
                    hitRateLimit = true
                    break
                } catch RiotAPIError.network {
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
        // A prompt that couldn't show (another sheet was up) mustn't stay
        // raised forever; the next 401 raises it again.
        APIKeyPrompt.shared.riotKeyRejected = false
        let region = platform.region
        let client = RiotAPIClient.shared
        let puuid = try await client.resolvePUUID(gameName: gameName, tagLine: tagLine, region: region)
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

    /// Linking a different account starts clean: the old account's games
    /// (with their AI reviews and coach chats, which cascade), its rank and
    /// the widget's last match all go. Runs before the import, so a failed
    /// sync can't leave the old games under the new name.
    ///
    /// A game's owner is its linked player's puuid, but puuids change with the
    /// API key (see `apiKeyFingerprintDefaultsKey`), so they are only compared
    /// on games imported under the current key. That per-game check also
    /// cleans a store that already mixes accounts. A different Riot ID is a
    /// switch unless one of those games belongs to the new puuid — then it's
    /// the same player, renamed.
    ///
    /// ponytail: a rename right after a key change (no comparable games yet)
    /// still reads as a switch; store the account's puuid per key if that
    /// starts to matter.
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
        for match in foreign { context.delete(match) }

        if switched, let existing {
            // Reset in place rather than deleted: an empty account list, even
            // for a moment, would swap ContentView to onboarding mid-sync.
            existing.profileIconID = nil
            existing.summonerLevel = nil
            existing.lastLeagueSyncDate = nil
            existing.lastTFTSyncDate = nil
            existing.lastRiotActivityDate = nil
            applyRank(nil, to: existing)
        }
        guard switched || !foreign.isEmpty else { return }
        WidgetSnapshotWriter.clear()
        UserDefaults.standard.removeObject(forKey: "trendDiagnosis")
        UserDefaults.standard.removeObject(forKey: "trendDiagnosisKey")
        try context.save()
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
            } catch RiotAPIError.unauthorized {
                // The key expired mid-sync: stop, and leave the rest for the
                // next key rather than writing them off as unavailable.
                throw RiotAPIError.unauthorized
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
        } catch RiotAPIError.unauthorized {
            throw RiotAPIError.unauthorized
        } catch {
            // No timeline exists for this game (old, or a mode without one) —
            // nothing a retry would change.
        }

        let match = existing ?? newMatch(id: matchID, game: .league)
        if existing == nil { context.insert(match) }
        // A review written without the timeline never saw the gold curve or
        // the head-to-head; let it be rewritten now that they exist.
        if timeline != nil, existing?.goldTimeline.isEmpty == true { match.reviewText = nil }
        populate(match, from: detail, focus: puuid, linkedPUUID: puuid, timeline: timeline, context: context)
        match.importVersion = complete ? currentDataVersion : 0
        return complete
    }

    /// Keeps a browsed copy from colliding with the player's own copy of the
    /// same game (`Match.id` is unique), and one viewer's copy from another's:
    /// the performance card belongs to whoever's profile it was opened from.
    static func browsedID(for matchID: String, viewer: String) -> String {
        "browsed:\(viewer):\(matchID)"
    }

    /// Another player's game as a full `Match`, from the cache when possible,
    /// so their profile lists games with the same rows as your own and opening
    /// one costs nothing more.
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
        return browsedMatch(detail: detail, viewedPuuid: viewedPuuid, context: context)
    }

    /// A browsable copy of another player's match, so their history opens the
    /// same way the player's own does. It is a cache: keyed so it never
    /// collides with real history, nobody in it is "you", and it skips the
    /// timeline call — the gold chart and head-to-head degrade gracefully.
    private static func browsedMatch(
        detail: RiotMatchResponse,
        viewedPuuid: String,
        context: ModelContext
    ) -> Match? {
        let id = browsedID(for: detail.metadata.matchId, viewer: viewedPuuid)
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
