import Foundation

/// The stat shards under the rune trees. Unlike other runes they aren't in `runesReforged.json`,
/// so this table supplies their names and icons (art lives in `perk-images/StatMods/`).
enum StatShard {
    struct Info {
        let name: String
        let effect: String
        /// Path under Data Dragon's `cdn/img/`, like rune icons, so `runeIconURL(for:)` serves both.
        let iconPath: String
    }

    /// By Riot's perk id. One table, not per row: the row is implied by the position in `statPerks`.
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

    private static func file(_ name: String) -> String {
        "perk-images/StatMods/\(name).png"
    }
}
