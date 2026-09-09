import Foundation

struct PlayerAggregateStats {
    let winRate: Double
    let averageKDA: Double
    let gamesSampled: Int
    let topChampion: String?

    static let empty = PlayerAggregateStats(winRate: 0, averageKDA: 0, gamesSampled: 0, topChampion: nil)
}

enum FriendComparisonService {
    static func aggregate(_ matches: [OtherPlayerMatchSummary]) -> PlayerAggregateStats {
        guard !matches.isEmpty else { return .empty }
        let wins = matches.filter(\.win).count
        let kdas = matches.map { match -> Double in
            match.deaths == 0 ? Double(match.kills + match.assists) : Double(match.kills + match.assists) / Double(match.deaths)
        }
        let topChampion = Dictionary(grouping: matches, by: \.champion)
            .max { $0.value.count < $1.value.count }?
            .key

        return PlayerAggregateStats(
            winRate: Double(wins) / Double(matches.count) * 100,
            averageKDA: kdas.reduce(0, +) / Double(kdas.count),
            gamesSampled: matches.count,
            topChampion: topChampion
        )
    }
}
