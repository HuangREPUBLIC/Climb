import Foundation

/// VALORANT uses its own regional routing values (distinct from RiotRegion,
/// which serves Account-V1/Match-V5/TFT-Match-V1). Not selectable in the UI
/// yet — VAL-MATCH-V1 requires Riot's elevated API approval, which personal
/// keys do not get (confirmed on developer.riotgames.com). This scaffold
/// exists so VALORANT sync is a toggle-and-wire addition, not a rebuild,
/// once/if that access is granted.
enum RiotValorantRegion: String, CaseIterable, Identifiable, Codable {
    case na, eu, ap, kr, latam, br

    var id: String { rawValue }
}
