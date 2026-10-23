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
        let games = matches.filter { $0.leagueStats != nil }
        let stats = games.compactMap(\.leagueStats)
        guard !stats.isEmpty else { return .empty }
        let takedowns = stats.map { $0.kills + $0.assists }.reduce(0, +)
        let deaths = stats.map(\.deaths).reduce(0, +)
        return PlayerAggregateStats(
            winRate: Double(games.filter(\.win).count) / Double(games.count) * 100,
            kda: Double(takedowns) / Double(max(deaths, 1)),
            topChampion: Dictionary(grouping: stats, by: \.champion).max { $0.value.count < $1.value.count }?.key
        )
    }
}
