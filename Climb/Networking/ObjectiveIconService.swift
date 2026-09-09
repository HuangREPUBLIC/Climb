import Foundation

/// Real in-game objective art (each elemental drake has its own icon), pulled
/// from CommunityDragon's minimap icon set. Data Dragon ships no objective
/// art at all, which is why this uses the community mirror the same way
/// RankEmblemService does for rank emblems.
enum ObjectiveIconService {
    private static let base = "https://raw.communitydragon.org/latest/game/assets/ux/minimap/icons"

    /// Riot's `monsterSubType` → the drake's icon filename.
    private static let dragonFiles: [String: String] = [
        "FIRE_DRAGON": "dragon_infernal",
        "WATER_DRAGON": "dragon_ocean",
        "AIR_DRAGON": "dragon_cloud",
        "EARTH_DRAGON": "dragon_mountain",
        "HEXTECH_DRAGON": "dragon_hextech",
        "CHEMTECH_DRAGON": "dragon_chemtech",
        "ELDER_DRAGON": "dragon_elder"
    ]

    static func dragonURL(subType: String) -> URL? {
        let file = dragonFiles[subType] ?? "dragon"
        return URL(string: "\(base)/\(file).png")
    }

    static func url(named file: String) -> URL? {
        URL(string: "\(base)/\(file).png")
    }

    static var baronURL: URL? { url(named: "baron") }
    static var heraldURL: URL? { url(named: "riftherald") }
    static var voidgrubURL: URL? { url(named: "grub") }
    static var turretURL: URL? { url(named: "tower") }
    static var inhibitorURL: URL? { url(named: "inhibitor") }

    /// Official lane position icons. The champ-select plugin only ships these
    /// as SVG (which AsyncImage cannot decode); the parties plugin has the
    /// same art as PNG, which is why the URL points there.
    private static let positionBase = "https://raw.communitydragon.org/latest/plugins/rcp-fe-lol-parties/global/default"

    static func positionURL(role: String) -> URL? {
        let file: String
        switch role {
        case "Top": file = "icon-position-top"
        case "Jungle": file = "icon-position-jungle"
        case "Mid": file = "icon-position-middle"
        case "ADC": file = "icon-position-bottom"
        case "Support": file = "icon-position-utility"
        default: return nil
        }
        return URL(string: "\(positionBase)/\(file).png")
    }

    static func dragonName(subType: String) -> String {
        switch subType {
        case "FIRE_DRAGON": return "Infernal"
        case "WATER_DRAGON": return "Ocean"
        case "AIR_DRAGON": return "Cloud"
        case "EARTH_DRAGON": return "Mountain"
        case "HEXTECH_DRAGON": return "Hextech"
        case "CHEMTECH_DRAGON": return "Chemtech"
        case "ELDER_DRAGON": return "Elder"
        default: return "Dragon"
        }
    }
}
