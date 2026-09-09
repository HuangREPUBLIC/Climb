import Foundation

enum Game: String, Codable, CaseIterable, Identifiable {
    case league = "League of Legends"
    case tft = "TFT"
    case valorant = "VALORANT"

    var id: String { rawValue }

    var shortName: String {
        switch self {
        case .league: return "LoL"
        case .tft: return "TFT"
        case .valorant: return "VALORANT"
        }
    }

    var systemImageName: String {
        switch self {
        case .league: return "shield.lefthalf.filled"
        case .tft: return "checkerboard.rectangle"
        case .valorant: return "scope"
        }
    }
}
