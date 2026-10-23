import Foundation

/// Recurring patterns in recent League games, computed here so the AI only explains exact numbers.
struct TrendSummary {
    /// Fewer games than this and a "pattern" is one bad night.
    static let minimumGames = 5

    /// One comparison the card draws as two bars, e.g. "Deaths per game: you 7.1, lobby 5.4".
    struct Signal: Identifiable {
        let label: String
        let mine: Double
        let theirs: Double
        var mineLabel = "You"
        /// What `mine` is measured against: "Lobby", "Opponent".
        let theirsLabel: String
        var digits = 1
        let isWeakness: Bool
        var id: String { label }

        var yours: String { String(format: "%.\(digits)f", mine) }
        var baseline: String { "\(theirsLabel.lowercased()) \(String(format: "%.\(digits)f", theirs))" }
    }

    let games: Int
    let wins: Int
    let signals: [Signal]
    let promptLines: [String]

    /// Newest game first; only games with a full scoreboard count.
    init(matches: [Match]) {
        let games = Array(matches.filter { $0.leagueStats != nil && $0.focusParticipant != nil }.prefix(20))
        self.games = games.count
        self.wins = games.filter(\.win).count

        func average(_ values: [Double]) -> Double {
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        var signals: [Signal] = []
        var lines: [String] = []

        let myDeaths = average(games.compactMap { $0.focusParticipant.map { Double($0.deaths) } })
        let lobbyDeaths = average(games.flatMap { match in
            match.participants.filter { $0.puuid != match.focusParticipant?.puuid }.map { Double($0.deaths) }
        })
        signals.append(Signal(label: "Deaths per game", mine: myDeaths, theirs: lobbyDeaths, theirsLabel: "Lobby", isWeakness: lobbyDeaths > 0 && myDeaths > lobbyDeaths * 1.2))

        var myCS: [Double] = [], theirCS: [Double] = []
        var laneKills = 0, laneDeaths = 0
        var matchups: [String: (games: Int, wins: Int)] = [:]
        for match in games {
            guard let me = match.focusParticipant, let opponent = match.laneOpponent(of: me) else { continue }
            myCS.append(Double(me.creepScore) / match.minutes)
            theirCS.append(Double(opponent.creepScore) / match.minutes)
            if let duel = match.opponentEncounters.first(where: { $0.opponentPuuid == opponent.puuid }) {
                laneKills += duel.killsOnOpponent
                laneDeaths += duel.deathsToOpponent
            }
            var record = matchups[opponent.champion] ?? (0, 0)
            record.games += 1
            if match.win { record.wins += 1 }
            matchups[opponent.champion] = record
        }
        if !myCS.isEmpty {
            let mine = average(myCS), theirs = average(theirCS)
            signals.append(Signal(label: "Minions / min", mine: mine, theirs: theirs, theirsLabel: "Opponent", isWeakness: mine < theirs - 0.5))
        }
        if laneKills + laneDeaths > 0 {
            signals.append(Signal(label: "Lane duels", mine: Double(laneKills), theirs: Double(laneDeaths), mineLabel: "Won", theirsLabel: "Lost", digits: 0, isWeakness: laneDeaths > laneKills))
        }

        // Vision against the lobby, per minute so game length doesn't skew it.
        let myVision = average(games.compactMap { match in match.focusParticipant.map { Double($0.visionScore) / match.minutes } })
        let lobbyVision = average(games.flatMap { match in
            match.participants.filter { $0.puuid != match.focusParticipant?.puuid }.map { Double($0.visionScore) / match.minutes }
        })
        signals.append(Signal(label: "Vision / min", mine: myVision, theirs: lobbyVision, theirsLabel: "Lobby", isWeakness: lobbyVision > 0 && myVision < lobbyVision * 0.8))

        // Leads that turned into losses: ahead by 1,500+ gold at 15 minutes.
        var ahead = 0, thrown = 0
        for match in games {
            guard let lead = match.goldTimeline.first(where: { $0.minute == 15 })?.goldDifference, lead >= 1_500 else { continue }
            ahead += 1
            if !match.win { thrown += 1 }
        }
        if ahead > 0 {
            signals.append(Signal(label: "Leads at 15 thrown", mine: Double(thrown), theirs: Double(ahead), mineLabel: "Thrown", theirsLabel: "Leads", digits: 0, isWeakness: thrown * 2 >= ahead))
        }

        self.signals = signals

        lines.append("Last \(games.count) League games: \(wins)W-\(games.count - wins)L.")
        for signal in signals {
            lines.append("\(signal.label): \(signal.yours) (\(signal.baseline))\(signal.isWeakness ? " — a weakness" : "").")
        }
        let kp = average(games.compactMap { match -> Double? in
            guard let me = match.focusParticipant, let share = match.killShare(of: me) else { return nil }
            return share * 100
        })
        lines.append("Average kill participation \(Int(kp.rounded()))%.")

        let byChampion: [String: [Match]] = Dictionary(grouping: games) { $0.leagueStats?.champion ?? "" }
        let championRecords: [String] = byChampion
            .sorted { $0.value.count > $1.value.count }
            .prefix(4)
            .map { champion, played in
                let won = played.filter(\.win).count
                return "\(champion) \(won)W-\(played.count - won)L"
            }
        lines.append("Champions: \(championRecords.joined(separator: ", ")).")

        let hardMatchups = matchups
            .filter { $0.value.games >= 2 && $0.value.wins * 2 < $0.value.games }
            .map { "\($0.key) \($0.value.wins)W-\($0.value.games - $0.value.wins)L" }
        if !hardMatchups.isEmpty {
            lines.append("Lane opponents they keep losing to: \(hardMatchups.joined(separator: ", ")).")
        }

        var tagCounts: [String: Int] = [:]
        for match in games { for tag in match.tags { tagCounts[tag, default: 0] += 1 } }
        if !tagCounts.isEmpty {
            lines.append("Their own tags on these games: \(tagCounts.sorted { $0.value > $1.value }.map { "\($0.key) ×\($0.value)" }.joined(separator: ", ")).")
        }
        self.promptLines = lines
    }
}
