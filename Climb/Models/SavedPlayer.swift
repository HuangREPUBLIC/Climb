import Foundation
import SwiftData

/// A player followed from their profile, listed under Following on the
/// Search tab so they're one tap away instead of a Riot ID to retype.
@Model
final class SavedPlayer {
    /// "name#tag", lowercased — Riot IDs are case-insensitive.
    @Attribute(.unique) var key: String
    var gameName: String
    var tagLine: String
    var platform: String
    var addedAt: Date = Date.now

    init(gameName: String, tagLine: String, platform: String) {
        self.key = Self.key(gameName: gameName, tagLine: tagLine)
        self.gameName = gameName
        self.tagLine = tagLine
        self.platform = platform
    }

    var riotID: String { "\(gameName)#\(tagLine)" }

    static func key(gameName: String, tagLine: String) -> String {
        "\(gameName)#\(tagLine)".lowercased()
    }
}
