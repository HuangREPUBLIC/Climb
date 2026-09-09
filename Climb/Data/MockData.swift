import Foundation
import SwiftData

enum MockData {
    static func seedIfNeeded(context: ModelContext) {
        let descriptor = FetchDescriptor<Match>()
        let existingCount = (try? context.fetchCount(descriptor)) ?? 0
        guard existingCount == 0 else { return }

        for match in sampleMatches() {
            context.insert(match)
        }
        try? context.save()
    }

    private static func sampleMatches() -> [Match] {
        let calendar = Calendar.current
        let now = Date()

        func daysAgo(_ n: Int) -> Date {
            calendar.date(byAdding: .day, value: -n, to: now) ?? now
        }

        let raw: [(champion: String, role: String, k: Int, d: Int, a: Int, cs: Int, win: Bool, queue: String, durationMin: Int, daysAgo: Int, notes: String)] = [
            ("Ahri", "Mid", 8, 2, 10, 182, true, "Ranked Solo", 28, 0, "Good roams after level 6, snowballed top."),
            ("Lee Sin", "Jungle", 4, 6, 5, 140, false, "Ranked Solo", 32, 1, "Overextended on the level 3 gank, lost tempo."),
            ("Jinx", "ADC", 11, 3, 7, 210, true, "Ranked Solo", 34, 2, ""),
            ("Thresh", "Support", 1, 4, 15, 25, true, "Ranked Solo", 30, 3, "Landed every hook in lane, carried through vision."),
            ("Darius", "Top", 6, 5, 3, 165, false, "Ranked Solo", 26, 5, "Got kited by ranged toplaner, need tenacity earlier."),
            ("Ahri", "Mid", 3, 7, 4, 150, false, "Ranked Solo", 29, 6, ""),
            ("Kai'Sa", "ADC", 9, 1, 6, 198, true, "Ranked Solo", 31, 8, "Clean game, itemised around their tank front line."),
            ("Vi", "Jungle", 7, 3, 9, 155, true, "Ranked Flex", 27, 10, "")
        ]

        return raw.map { entry in
            let match = Match(
                id: UUID().uuidString,
                game: .league,
                win: entry.win,
                queueType: entry.queue,
                gameDurationSeconds: entry.durationMin * 60,
                timestamp: daysAgo(entry.daysAgo),
                notes: entry.notes,
                isMockData: true
            )
            match.leagueStats = LeagueStats(
                champion: entry.champion,
                role: entry.role,
                kills: entry.k,
                deaths: entry.d,
                assists: entry.a,
                creepScore: entry.cs
            )
            return match
        }
    }
}
