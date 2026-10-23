import Foundation

/// The vocabulary behind a match's reflection tags. Free text can't be charted or filtered ("bad
/// vision", "vision bad", "no wards" are three groups of one), so the editor leads with a fixed
/// set per game (the vocabularies differ: "lost lane" means nothing in TFT) and allows custom tags.
enum ReflectionTag {
    /// Deliberately short: a list long enough to scroll becomes something the player ignores.
    private static let league = [
        "Won lane",
        "Lost lane",
        "Bad matchup",
        "Died overextending",
        "Good vision",
        "Poor vision",
        "Good macro",
        "Bad macro",
        "Wrong build",
        "Threw a lead",
        "Tilted",
        "Team diff"
    ]

    private static let tft = [
        "Greedy econ",
        "Forced a comp",
        "Good positioning",
        "Bad positioning",
        "Bad items",
        "Highroll",
        "Lowroll",
        "Contested",
        "Tilted"
    ]

    /// Suggestions for `game` plus tags the player invented, so a custom tag returns as a chip.
    static func vocabulary(for game: Game, usedIn matches: [Match]) -> [String] {
        let suggestions = switch game {
        case .league: league
        case .tft: tft
        }
        let used = matches.flatMap(\.tags)
        var seen = Set<String>()
        return (suggestions + used).filter { seen.insert($0).inserted }
    }

    /// Trimmed, capped at 24, and matched case-insensitively so "tilted" isn't a second "Tilted".
    static func normalise(_ raw: String, against vocabulary: [String]) -> String? {
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let capped = String(trimmed.prefix(24))
        if let existing = vocabulary.first(where: { $0.caseInsensitiveCompare(capped) == .orderedSame }) {
            return existing
        }
        return capped
    }
}
