import Foundation

/// Recurring patterns across the player's recent League games — computed
/// here, deterministically, so the numbers on screen are exact and the AI
/// only has to explain them rather than invent them.
struct TrendSummary {
    /// One comparison the card can show: "Deaths per game 7.1 · lobby 5.4".
    struct Signal: Identifiable {
        let label: String
        let yours: String
        /// What `yours` is measured against, already worded: "lobby 5.4".
        let baseline: String
        /// True when the player is clearly worse than the baseline.
        let isWeakness: Bool
        var id: String { label }
    }

    let games: Int
    let wins: Int
    let signals: [Signal]
    /// Plain-text facts for the model, signals included.
    let promptLines: [String]

    /// Newest game first; only games with a full scoreboard count.
    init(matches: [Match]) {
        let games = Array(matches.filter { $0.leagueStats != nil && $0.focusParticipant != nil }.prefix(20))
        self.games = games.count
        self.wins = games.filter(\.win).count

        func average(_ values: [Double]) -> Double {
            values.isEmpty ? 0 : values.reduce(0, +) / Double(values.count)
        }
        func minutes(_ match: Match) -> Double { max(Double(match.gameDurationSeconds) / 60, 1) }
        func one(_ value: Double) -> String { String(format: "%.1f", value) }

        var signals: [Signal] = []
        var lines: [String] = []

        // Deaths against everyone else in the same lobbies.
        let myDeaths = average(games.compactMap { $0.focusParticipant.map { Double($0.deaths) } })
        let lobbyDeaths = average(games.flatMap { match in
            match.participants.filter { $0.puuid != match.focusParticipant?.puuid }.map { Double($0.deaths) }
        })
        signals.append(Signal(label: "Deaths per game", yours: one(myDeaths), baseline: "lobby \(one(lobbyDeaths))", isWeakness: lobbyDeaths > 0 && myDeaths > lobbyDeaths * 1.2))

        // Farming against the lane opponent, the only fair comparison.
        var myCS: [Double] = [], theirCS: [Double] = []
        var laneKills = 0, laneDeaths = 0
        var matchups: [String: (games: Int, wins: Int)] = [:]
        for match in games {
            guard let me = match.focusParticipant, me.role != "—",
                  let opponent = match.participants.first(where: { $0.teamId != me.teamId && $0.role == me.role })
            else { continue }
            myCS.append(Double(me.creepScore) / minutes(match))
            theirCS.append(Double(opponent.creepScore) / minutes(match))
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
            signals.append(Signal(label: "CS / min", yours: one(mine), baseline: "opponent \(one(theirs))", isWeakness: mine < theirs - 0.5))
        }
        if laneKills + laneDeaths > 0 {
            signals.append(Signal(label: "Lane duels won", yours: "\(laneKills)", baseline: "lost \(laneDeaths)", isWeakness: laneDeaths > laneKills))
        }

        // Vision against the lobby, per minute so game length doesn't skew it.
        let myVision = average(games.compactMap { match in match.focusParticipant.map { Double($0.visionScore) / minutes(match) } })
        let lobbyVision = average(games.flatMap { match in
            match.participants.filter { $0.puuid != match.focusParticipant?.puuid }.map { Double($0.visionScore) / minutes(match) }
        })
        signals.append(Signal(label: "Vision / min", yours: one(myVision), baseline: "lobby \(one(lobbyVision))", isWeakness: lobbyVision > 0 && myVision < lobbyVision * 0.8))

        // Leads that turned into losses: ahead by 1,500+ gold at 15 minutes.
        var ahead = 0, thrown = 0
        for match in games {
            guard let lead = match.goldTimeline.first(where: { $0.minute == 15 })?.goldDifference, lead >= 1_500 else { continue }
            ahead += 1
            if !match.win { thrown += 1 }
        }
        if ahead > 0 {
            signals.append(Signal(label: "Leads at 15 lost", yours: "\(thrown)", baseline: "of \(ahead)", isWeakness: thrown * 2 >= ahead))
        }

        self.signals = signals

        lines.append("Last \(games.count) League games: \(wins)W-\(games.count - wins)L.")
        for signal in signals {
            lines.append("\(signal.label): \(signal.yours) (\(signal.baseline))\(signal.isWeakness ? " — a weakness" : "").")
        }
        let kp = average(games.compactMap { match -> Double? in
            guard let me = match.focusParticipant else { return nil }
            let teamKills = match.participants.filter { $0.teamId == me.teamId }.map(\.kills).reduce(0, +)
            return teamKills > 0 ? Double(me.kills + me.assists) / Double(teamKills) * 100 : nil
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
