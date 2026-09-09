import Foundation

/// The three stat shards a player picks under their rune trees.
///
/// Riot reports these in `perks.statPerks` as three plain ids, and — unlike
/// every other rune — they are *not* in `runesReforged.json`, so there is no
/// name or icon to look up there. Data Dragon serves their art from a fixed
/// `perk-images/StatMods/` folder instead, which is what this table is for.
enum StatShard {
    struct Info {
        let name: String
        let effect: String
        /// Path under Data Dragon's `cdn/img/`, matching how rune icons are
        /// addressed elsewhere so `runeIconURL(for:)` can serve both.
        let iconPath: String
    }

    /// Keyed by Riot's perk id. Every value Riot can send is listed once rather
    /// than split per row — which row a shard came from is implied by its
    /// position in `statPerks`, and a per-row table would be three places to
    /// get out of date instead of one.
    static func info(for id: Int) -> Info? {
        switch id {
        case 5001: return Info(name: "Health Scaling", effect: "Health that grows with level", iconPath: file("StatModsHealthScalingIcon"))
        case 5002: return Info(name: "Armor", effect: "Flat armour", iconPath: file("StatModsArmorIcon"))
        case 5003: return Info(name: "Magic Resist", effect: "Flat magic resist", iconPath: file("StatModsMagicResIcon"))
        case 5005: return Info(name: "Attack Speed", effect: "Bonus attack speed", iconPath: file("StatModsAttackSpeedIcon"))
        case 5007: return Info(name: "Ability Haste", effect: "Bonus ability haste", iconPath: file("StatModsCDRScalingIcon"))
        case 5008: return Info(name: "Adaptive Force", effect: "Attack damage or ability power, whichever suits the build", iconPath: file("StatModsAdaptiveForceIcon"))
        case 5010: return Info(name: "Move Speed", effect: "Percentage move speed", iconPath: file("StatModsMovementSpeedIcon"))
        case 5011: return Info(name: "Health", effect: "Flat health", iconPath: file("StatModsHealthPlusIcon"))
        case 5013: return Info(name: "Tenacity and Slow Resist", effect: "Reduced crowd control and slow duration", iconPath: file("StatModsTenacityIcon"))
        default: return nil
        }
    }

    static func isShard(_ id: Int) -> Bool { info(for: id) != nil }

    private static func file(_ name: String) -> String {
        "perk-images/StatMods/\(name).png"
    }
}
