import Foundation
import WidgetKit

/// Duplicated (not shared-target) in ClimbWidget/WidgetSnapshotReader.swift —
/// the widget extension can't see the main app's SwiftData models across
/// targets, so the app writes this tiny snapshot to the shared App Group
/// UserDefaults instead of exposing the whole store.
struct LatestMatchSnapshot: Codable {
    let champion: String
    let win: Bool
    let kills: Int
    let deaths: Int
    let assists: Int
    let queueType: String
    let timestamp: Date
}

enum WidgetSnapshotWriter {
    private static let suiteName = "group.climb"
    private static let key = "latestMatchSnapshot"

    static func write(_ snapshot: LatestMatchSnapshot) {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }

    /// After switching accounts, so the widget doesn't show the old one's game.
    static func clear() {
        UserDefaults(suiteName: suiteName)?.removeObject(forKey: key)
        WidgetCenter.shared.reloadAllTimelines()
    }
}
