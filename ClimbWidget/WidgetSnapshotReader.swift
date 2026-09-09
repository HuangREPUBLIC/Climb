import Foundation

/// Duplicated (not shared-target) from Climb/Services/WidgetSnapshotWriter.swift
/// — see that file for why.
struct LatestMatchSnapshot: Codable {
    let champion: String
    let win: Bool
    let kills: Int
    let deaths: Int
    let assists: Int
    let queueType: String
    let timestamp: Date
}

enum WidgetSnapshotReader {
    private static let suiteName = "group.climb"
    private static let key = "latestMatchSnapshot"

    static func read() -> LatestMatchSnapshot? {
        guard let defaults = UserDefaults(suiteName: suiteName) else { return nil }
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(LatestMatchSnapshot.self, from: data)
    }
}
