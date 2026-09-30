import Foundation

struct PlayerAggregateStats {
    let winRate: Double
    /// Totals over totals, as op.gg does, so one 10/0/10 game can't pass for
    /// an average.
    let kda: Double
    let topChampion: String?

    static let empty = PlayerAggregateStats(winRate: 0, kda: 0, topChampion: nil)
}

enum FriendComparisonService {
    static func aggregate(_ matches: [Match]) -> PlayerAggregateStats {
        aggregate(matches.compactMap { match in
            match.leagueStats.map { ($0.champion, $0.kills, $0.deaths, $0.assists, match.win) }
        })
    }

    private static func aggregate(_ lines: [(champion: String, kills: Int, deaths: Int, assists: Int, win: Bool)]) -> PlayerAggregateStats {
        guard !lines.isEmpty else { return .empty }
        let takedowns = lines.map { $0.kills + $0.assists }.reduce(0, +)
        let deaths = lines.map(\.deaths).reduce(0, +)
        return PlayerAggregateStats(
            winRate: Double(lines.filter(\.win).count) / Double(lines.count) * 100,
            kda: Double(takedowns) / Double(max(deaths, 1)),
            topChampion: Dictionary(grouping: lines, by: \.champion).max { $0.value.count < $1.value.count }?.key
        )
    }
}
