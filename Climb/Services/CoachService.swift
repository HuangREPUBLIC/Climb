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

    private static func buildSystemPrompt(for match: Match, allMatches: [Match]) async -> String {
        var lines = [
            "You are Climb's AI coach, a supportive but honest coach for League of Legends and TFT.",
            "Ground every answer in the player's own stats below — never give generic strategy advice.",
            // The app parses this shape into a verdict, findings and one action
            // (see CoachReply). Prose still renders, just as a plain paragraph,
            // so these are instructions rather than a contract the app relies on.
            "Answer in this shape, and keep it short — the player is reading on a phone:",
            "1. One sentence of verdict, under 140 characters, on its own first line.",
            "2. Up to three findings, each on its own line starting with '- ', one clause each.",
            "3. One line starting with 'Try:' naming a single concrete thing to do next game.",
            "Cite the player's actual numbers inside the findings. No headings, no preamble, no sign-off."
        ]

        if let stats = match.leagueStats {
            lines.append("This match: \(stats.champion) (\(stats.role)), KDA \(stats.kills)/\(stats.deaths)/\(stats.assists), CS \(stats.creepScore), \(match.win ? "won" : "lost").")
            var itemNames: [String] = []
            for id in stats.items where id != 0 {
                if let name = await DataDragonService.shared.itemInfo(for: id)?.name { itemNames.append(name) }
            }
            if !itemNames.isEmpty {
                lines.append("Final items: \(itemNames.joined(separator: ", ")).")
            }
        } else if let stats = match.tftStats {
            lines.append("This match: TFT, placed #\(stats.placement), level \(stats.level), traits: \(stats.traits.joined(separator: ", ")).")
        }

        if !match.notes.isEmpty {
            lines.append("Player's own note on this match: \"\(match.notes)\"")
        }

        if !match.tags.isEmpty {
            lines.append("Player tagged this match: \(match.tags.joined(separator: ", ")).")
        }

        let recentLeague = allMatches.filter { $0.leagueStats != nil }.prefix(10)
        if !recentLeague.isEmpty {
            let wins = recentLeague.filter(\.win).count
            lines.append("Recent League form (last \(recentLeague.count)): \(wins)W-\(recentLeague.count - wins)L.")
        }

        // The journal is the thing no stats site has. A recurring self-diagnosis
        // — "Tilted" on six of the last twenty — is exactly the kind of pattern
        // the coach should be allowed to name, and it can only come from here.
        var tagCounts: [String: Int] = [:]
        for match in allMatches.prefix(20) {
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
}
