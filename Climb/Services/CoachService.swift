import Foundation
import SwiftData

@MainActor
enum CoachService {
    static func conversation(for match: Match, context: ModelContext) -> CoachConversation {
        if let existing = match.coachConversation {
            return existing
        }
        let conversation = CoachConversation(match: match)
        match.coachConversation = conversation
        context.insert(conversation)
        try? context.save()
        return conversation
    }

    static func send(
        userMessage: String,
        conversation: CoachConversation,
        match: Match,
        allMatches: [Match],
        context: ModelContext
    ) async throws {
        // Enforced here, not only by hiding the button: everything the coach
        // is told ("your recent form", "your tags") assumes the game is the
        // user's, so a browsed game would be analysed against the wrong person.
        guard match.isOwnHistory else { throw AICoachError.notYourGame }
        let historyBeforeReply = conversation.messages

        let playerMessage = ChatMessage(role: .player, text: userMessage)
        playerMessage.conversation = conversation
        conversation.messages.append(playerMessage)
        context.insert(playerMessage)
        try? context.save()

        let systemPrompt = await buildSystemPrompt(for: match, allMatches: allMatches)
        let reply: String
        do {
            reply = try await AICoachClient.shared.send(
                systemPrompt: systemPrompt,
                history: historyBeforeReply,
                newUserMessage: userMessage
            )
        } catch {
            // An unanswered question left in the history reads as though the
            // coach ignored it, and would be resent as context next time.
            conversation.messages.removeAll { $0 === playerMessage }
            context.delete(playerMessage)
            try? context.save()
            throw error
        }

        let coachMessage = ChatMessage(role: .coach, text: reply)
        coachMessage.conversation = conversation
        conversation.messages.append(coachMessage)
        context.insert(coachMessage)
        try? context.save()
    }

    /// Reviews being written, by match id. The request belongs here rather
    /// than to the card: leaving the screen mustn't throw away a reply already
    /// paid for, and coming back should wait for it instead of asking again.
    private static var reviewsInFlight: [String: Task<Void, Error>] = [:]

    /// The post-game review card: one reply, generated the first time a match
    /// is opened and kept on the match so reopening it costs nothing.
    static func review(match: Match, allMatches: [Match], context: ModelContext) async throws {
        guard match.isOwnHistory else { throw AICoachError.notYourGame }
        if let running = reviewsInFlight[match.id] { return try await running.value }

        let matchID = match.id
        let task = Task { @MainActor in
            defer { reviewsInFlight[matchID] = nil }
            let systemPrompt = await buildSystemPrompt(for: match, allMatches: allMatches)
            let reply = try await AICoachClient.shared.send(
                systemPrompt: systemPrompt,
                history: [],
                newUserMessage: "Review this game for me: what decided it, and what should I change next game?"
            )
            match.reviewText = reply
            try? context.save()
        }
        reviewsInFlight[matchID] = task
        try await task.value
    }

    /// The trend card's read of `TrendSummary`: what keeps costing games and
    /// the one habit to fix first. One request at a time, for the same reason
    /// as reviews.
    private static var diagnosesInFlight: [String: Task<String, Error>] = [:]

    /// `key` identifies the set of games summarised; a request for one set
    /// is never handed to a caller asking about another.
    static func diagnose(_ summary: TrendSummary, key: String) async throws -> String {
        if let running = diagnosesInFlight[key] { return try await running.value }
        let prompt = [
            "You are Climb's AI coach, a supportive but honest coach for League of Legends.",
            "Below are patterns computed from the player's last \(summary.games) games. Name what recurs across them — never a single game, never generic advice."
        ] + replyFormat + summary.promptLines
        let task = Task { @MainActor in
            defer { diagnosesInFlight[key] = nil }
            return try await AICoachClient.shared.send(
                systemPrompt: prompt.joined(separator: "\n"),
                history: [],
                newUserMessage: "What keeps costing me games, and what should I fix first?"
            )
        }
        diagnosesInFlight[key] = task
        return try await task.value
    }

    /// The app parses this shape into a verdict, findings and one action (see
    /// CoachReply). Prose still renders, just as a plain paragraph, so these
    /// are instructions rather than a contract the app relies on.
    private static var replyFormat: [String] {
        [
            "Answer in this shape, and keep it short — the player is reading on a phone:",
            "1. One sentence of verdict, under 140 characters, on its own first line.",
            "2. Up to three findings, each on its own line starting with '- ', one clause each.",
            "3. One line starting with 'Try:' naming a single concrete thing to do next game.",
            "Cite the player's actual numbers inside the findings. No headings, no preamble, no sign-off.",
            "Write in \(replyLanguage), but keep the '- ' markers and the literal 'Try:' prefix so the app can lay the reply out."
        ]
    }

    private static func buildSystemPrompt(for match: Match, allMatches: [Match]) async -> String {
        var lines = [
            "You are Climb's AI coach, a supportive but honest coach for League of Legends and TFT.",
            "Ground every answer in the player's own stats below — never give generic strategy advice."
        ] + replyFormat

        // Browsed copies of other players' games live in the same store, and
        // the caller's order isn't guaranteed — newest first, own games only.
        let ownMatches = allMatches.filter(\.isOwnHistory).sorted { $0.timestamp > $1.timestamp }

        if let stats = match.leagueStats {
            lines += await leagueFacts(for: match, stats: stats, ownMatches: ownMatches)
        } else if let stats = match.tftStats {
            lines.append("This match: TFT, placed #\(stats.placement), level \(stats.level), traits: \(stats.traits.joined(separator: ", ")).")
        }

        if !match.notes.isEmpty {
            lines.append("Player's own note on this match: \"\(match.notes)\"")
        }
        if !match.tags.isEmpty {
            lines.append("Player tagged this match: \(match.tags.joined(separator: ", ")).")
        }

        // The journal is the thing no stats site has. A recurring self-diagnosis
        // — "Tilted" on six of the last twenty — is exactly the kind of pattern
        // the coach should be allowed to name, and it can only come from here.
        var tagCounts: [String: Int] = [:]
        for match in ownMatches.prefix(20) {
            for tag in match.tags { tagCounts[tag, default: 0] += 1 }
        }
        if !tagCounts.isEmpty {
            let recurring = tagCounts
                .sorted { $0.value == $1.value ? $0.key < $1.key : $0.value > $1.value }
                .prefix(4)
                .map { "\($0.key) (\($0.value))" }
                .joined(separator: ", ")
            lines.append("Tags the player keeps applying to their recent games: \(recurring).")
        }

        return lines.joined(separator: "\n")
    }

    /// Everything stored about one League game, as the facts the model reads.
    /// The coach can't watch the game, so any number left out here is a
    /// question it can only answer generically.
    private static func leagueFacts(for match: Match, stats: LeagueStats, ownMatches: [Match]) async -> [String] {
        var lines: [String] = []
        let minutes = max(Double(match.gameDurationSeconds) / 60, 1)
        func perMinute(_ value: Int) -> String { String(format: "%.1f", Double(value) / minutes) }
        func percent(_ part: Int, of whole: Int) -> Int {
            whole > 0 ? Int((Double(part) / Double(whole) * 100).rounded()) : 0
        }

        // Everything is read before the one `await` (item names, at the end):
        // a launch rebuild may replace these rows while that lookup runs.
        let itemIDs = stats.items.filter { $0 != 0 }
        let champion = stats.champion
        let position = OPGGPosition(role: stats.role)
        var laneOpponentChampion: String?
        let me = match.focusParticipant
        let team = match.participants.filter { $0.teamId == me?.teamId }
        let takedowns = stats.kills + stats.assists

        lines.append("This game: \(stats.champion) \(stats.role), \(match.win ? "won" : "lost"), \(match.queueType), \(match.gameDurationSeconds / 60) minutes.")
        var combat = "KDA \(stats.kills)/\(stats.deaths)/\(stats.assists) (\(String(format: "%.2f", stats.kda)))"
        // Without the scoreboard these would read as a confident "0%".
        if !team.isEmpty {
            combat += ", kill participation \(percent(takedowns, of: team.map(\.kills).reduce(0, +)))%, \(percent(stats.damageDealtToChampions, of: team.map(\.damageDealtToChampions).reduce(0, +)))% of the team's champion damage"
        }
        lines.append(combat + " (\(stats.damageDealtToChampions) damage), \(stats.damageTaken) damage taken.")
        lines.append("Economy: \(stats.creepScore) CS (\(perMinute(stats.creepScore))/min), \(stats.goldEarned) gold (\(perMinute(stats.goldEarned))/min). Vision score \(stats.visionScore) (\(perMinute(stats.visionScore))/min), \(stats.wardsPlaced) wards placed, \(stats.wardsKilled) cleared.")

        if let me, let rank = PerformanceScore.rank(for: me, in: match) {
            let score = PerformanceScore.compute(for: me, in: match)
            lines.append("Climb's performance score: \(String(format: "%.1f", score))/10, \(rank) of \(match.participants.count) in this lobby (lobby average \(PerformanceScore.lobbyAverage)).")
        }

        var highlights: [String] = []
        if stats.pentaKills > 0 { highlights.append("pentakill") }
        else if stats.quadraKills > 0 { highlights.append("quadra kill") }
        else if stats.tripleKills > 0 { highlights.append("triple kill") }
        if stats.soloKills > 0 { highlights.append("\(stats.soloKills) solo kills") }
        if stats.firstBloodKill { highlights.append("first blood") }
        if stats.turretKills > 0 { highlights.append("\(stats.turretKills) turrets") }
        let dragons = stats.dragonKillsByType.values.reduce(0, +)
        if dragons > 0 { highlights.append("\(dragons) dragons") }
        if stats.riftHeraldKills + stats.voidgrubKills > 0 { highlights.append("\(stats.riftHeraldKills) heralds, \(stats.voidgrubKills) voidgrubs") }
        if stats.objectivesStolen > 0 { highlights.append("\(stats.objectivesStolen) objectives stolen") }
        if !highlights.isEmpty { lines.append("Highlights: \(highlights.joined(separator: ", ")).") }

        // The lane opponent, and who actually won the fights between you —
        // reconstructed from the timeline at import.
        if let me, me.role != "—",
           let opponent = match.participants.first(where: { $0.teamId != me.teamId && $0.role == me.role }) {
            laneOpponentChampion = opponent.champion
            var line = "Lane opponent: \(opponent.champion), \(opponent.kills)/\(opponent.deaths)/\(opponent.assists), \(opponent.creepScore) CS, \(opponent.goldEarned) gold, \(opponent.damageDealtToChampions) champion damage."
            if let duel = match.opponentEncounters.first(where: { $0.opponentPuuid == opponent.puuid }) {
                line += " Head-to-head: the player killed them \(duel.killsOnOpponent) times and died to them \(duel.deathsToOpponent) times."
            }
            lines.append(line)
        }

        // The final frame repeats its minute (20:00 and a 20:30 ending share
        // "20"), so the last minute is left out rather than guessed at.
        let lastMinute = match.goldTimeline.map(\.minute).max() ?? 0
        let curve = Dictionary(
            match.goldTimeline.filter { $0.minute < lastMinute }.map { ($0.minute, $0.goldDifference) },
            uniquingKeysWith: { first, _ in first }
        )
        let checkpoints = [10, 15, 20].compactMap { minute in
            curve[minute].map { "\($0 >= 0 ? "+" : "")\($0) at \(minute) min" }
        }
        if !checkpoints.isEmpty {
            lines.append("Team gold lead (positive = the player's team ahead): \(checkpoints.joined(separator: ", ")).")
        }

        let onChampion = ownMatches.filter { $0.leagueStats?.champion == stats.champion }
        if onChampion.count > 1 {
            let wins = onChampion.filter(\.win).count
            lines.append("On \(stats.champion) across \(onChampion.count) stored games: \(wins)W-\(onChampion.count - wins)L.")
        }

        // Form coming into this game, not games played after it.
        let recent = ownMatches.filter { $0.leagueStats != nil && $0.timestamp < match.timestamp }.prefix(10)
        if !recent.isEmpty {
            let wins = recent.filter(\.win).count
            let scores = recent.compactMap { PerformanceScore.compute(for: $0) }
            let average = scores.isEmpty ? 0 : scores.reduce(0, +) / Double(scores.count)
            lines.append("League form going into this game (previous \(recent.count)): \(wins)W-\(recent.count - wins)L, average score \(String(format: "%.1f", average)).")
        }

        var itemNames: [String] = []
        for id in itemIDs {
            if let name = await DataDragonService.shared.itemInfo(for: id)?.name { itemNames.append(name) }
        }
        if !itemNames.isEmpty { lines.append("Final items: \(itemNames.joined(separator: ", ")).") }

        // This patch's meta from op.gg, so the coach can tell a build or a
        // matchup problem apart from a play problem. Best-effort: no line if
        // op.gg is unreachable.
        if let position, let meta = try? await OPGGClient.shared.analysis(champion: champion, position: position) {
            if let core = meta.coreItems {
                var coreNames: [String] = []
                for id in core.ids {
                    if let name = await DataDragonService.shared.itemInfo(for: id)?.name { coreNames.append(name) }
                }
                if !coreNames.isEmpty {
                    lines.append("op.gg's most-built core for \(champion) \(position.title) this patch: \(coreNames.joined(separator: " → ")) (\(Int((core.winRate * 100).rounded()))% win rate).")
                }
            }
            if let opponent = laneOpponentChampion {
                // Riot says "MonkeyKing", op.gg says "Wukong": compare ids.
                let dataDragon = DataDragonService.shared
                let opponentID = await dataDragon.resolvedChampionID(for: opponent)
                var duel: ChampionAnalysis.Counter?
                for counter in (meta.strongCounters ?? []) + (meta.weakCounters ?? []) {
                    if await dataDragon.resolvedChampionID(for: counter.championName) == opponentID {
                        duel = counter
                        break
                    }
                }
                // A handful of games is noise, not a matchup.
                if let duel, duel.play >= 50 {
                    lines.append("op.gg: \(champion) wins \(Int((duel.myWinRate * 100).rounded()))% of \(duel.play) games against \(duel.championName) in this lane this patch.")
                }
            }
        }
        return lines
    }

    /// The reader's language, named in English for the model — "Chinese".
    private static var replyLanguage: String {
        let code = Locale.preferredLanguages.first
            .flatMap { Locale(identifier: $0).language.languageCode?.identifier } ?? "en"
        return Locale(identifier: "en").localizedString(forLanguageCode: code) ?? "English"
    }
}
