import Foundation

/// Real in-game objective art, pulled from CommunityDragon's minimap icon set.
/// Data Dragon ships no objective art at all, which is why this uses the
/// community mirror.
enum ObjectiveIconService {
    private static let base = "https://raw.communitydragon.org/latest/game/assets/ux/minimap/icons"

    static func url(named file: String) -> URL? {
        URL(string: "\(base)/\(file).png")
    }
}
