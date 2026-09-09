import Foundation

/// Riot's *regional* routing values, which are separate from the platform a
/// summoner lives on: account lookups go to a platform host (`jp1`), match
/// history to a regional one (`asia`).
enum RiotRegion: String, CaseIterable, Identifiable, Codable {
    case americas
    case europe
    case asia
    /// Riot split SEA out of `americas` when it moved Oceania onto its own
    /// cluster; match-v5 returns nothing if a SEA platform is routed to
    /// `americas`, which is what used to happen to every OCE account here.
    case sea

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .americas: return "Americas"
        case .europe: return "Europe"
        case .asia: return "Asia"
        case .sea: return "SEA"
        }
    }
}
