import Foundation

/// The vocabulary behind a match's reflection tags.
///
/// Tags exist so the journal can be *queried* — "what happens to my win rate in
/// games I tagged Tilted?" — and free text alone can't answer that: "bad
/// vision", "vision bad" and "no wards" are three tags describing one habit, so
/// every entry becomes a group of one and nothing can be charted or filtered.
///
/// So the editor leads with a fixed set, and still allows a custom tag for the
/// things the set doesn't cover. The suggestions differ by game because the
/// self-review vocabulary genuinely differs: "lost lane" means nothing in TFT
/// and "greedy econ" means nothing in a Rift game.
enum ReflectionTag {
    static func suggestions(for game: Game) -> [String] {
        switch game {
        case .league:
            return league
        case .tft:
            return tft
        }
    }

    /// Deliberately short. A list long enough to need scrolling stops being
    /// something the player picks from and becomes something they ignore.
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

    /// Suggestions for `game`, plus anything the player has already invented,
    /// so a custom tag is offered as a chip the second time rather than having
    /// to be retyped exactly.
    static func vocabulary(for game: Game, usedIn matches: [Match]) -> [String] {
        let used = matches.flatMap(\.tags)
        var seen = Set<String>()
        return (suggestions(for: game) + used).filter { seen.insert($0).inserted }
    }

    /// Trimmed, length-capped, and matched case-insensitively against the
    /// existing vocabulary so "tilted" doesn't become a second "Tilted".
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

extension Match {
    /// Tags in the order the vocabulary lists them, so a match's chips don't
    /// reshuffle between views depending on the order they were tapped in.
    func orderedTags(for vocabulary: [String]) -> [String] {
        tags.sorted { lhs, rhs in
            let l = vocabulary.firstIndex(of: lhs) ?? .max
            let r = vocabulary.firstIndex(of: rhs) ?? .max
            return l == r ? lhs < rhs : l < r
        }
    }
}
