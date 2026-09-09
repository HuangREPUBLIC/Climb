import Foundation

/// Platform routing values, used by Summoner-V4 (unlike Account-V1/Match-V5/
/// TFT-Match-V1, which use the regional routing values in RiotRegion).
enum RiotPlatform: String, CaseIterable, Identifiable, Codable {
    case na1, br1, la1, la2
    case euw1, eun1, tr1, ru, me1
    case kr, jp1
    case oc1, sg2, tw2, vn2, ph2, th2

    var id: String { rawValue }

    var region: RiotRegion {
        switch self {
        case .na1, .br1, .la1, .la2: return .americas
        case .euw1, .eun1, .tr1, .ru, .me1: return .europe
        case .kr, .jp1: return .asia
        // Oceania belongs here too — it was moved onto the SEA cluster and is
        // no longer reachable through `americas`.
        case .oc1, .sg2, .tw2, .vn2, .ph2, .th2: return .sea
        }
    }

    var displayName: String {
        switch self {
        case .na1: return "North America"
        case .br1: return "Brazil"
        case .la1: return "LAN"
        case .la2: return "LAS"
        case .oc1: return "Oceania"
        case .sg2: return "Singapore"
        case .tw2: return "Taiwan"
        case .vn2: return "Vietnam"
        case .ph2: return "Philippines"
        case .th2: return "Thailand"
        case .euw1: return "EU West"
        case .eun1: return "EU Nordic & East"
        case .tr1: return "Turkey"
        case .ru: return "Russia"
        case .me1: return "Middle East"
        case .kr: return "Korea"
        case .jp1: return "Japan"
        }
    }
}
