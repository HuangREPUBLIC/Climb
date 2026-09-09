import Foundation

/// Augments (the picks in Arena / Brawl / ARAM: Mayhem) are returned by
/// Match-V5 as bare numeric IDs in `playerAugment1...6`. Riot's Data Dragon
/// publishes no augment table at all, so names, descriptions and icons come
/// from CommunityDragon's Arena dump — the same mirror already used for rank
/// emblems and objective art.
actor AugmentService {
    static let shared = AugmentService()

    struct Augment: Identifiable {
        let id: Int
        let name: String
        let description: String
        let rarity: Int
        let iconPath: String

        var iconURL: URL? {
            URL(string: "https://raw.communitydragon.org/latest/game/\(iconPath.lowercased())")
        }
    }

    private var augmentsByID: [Int: Augment] = [:]
    private var didLoad = false

    func augment(id: Int) async -> Augment? {
        guard id != 0 else { return nil }
        if !didLoad { await load() }
        return augmentsByID[id]
    }

    func augments(ids: [Int]) async -> [Augment] {
        if !didLoad { await load() }
        return ids.filter { $0 != 0 }.compactMap { augmentsByID[$0] }
    }

    private func load() async {
        guard let url = URL(string: "https://raw.communitydragon.org/latest/cdragon/arena/en_us.json") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(AugmentResponse.self, from: data)
            augmentsByID = Dictionary(
                response.augments.map {
                    ($0.id, Augment(
                        id: $0.id,
                        name: $0.name,
                        description: Self.stripMarkup($0.desc ?? ""),
                        rarity: $0.rarity ?? 0,
                        iconPath: $0.iconSmall ?? $0.iconLarge ?? ""
                    ))
                },
                uniquingKeysWith: { first, _ in first }
            )
            didLoad = true
        } catch {
            // Leave unloaded so a later view can retry; callers just render
            // the slot without a label in the meantime.
        }
    }

    /// Descriptions carry three kinds of inline game markup: HTML-ish tags
    /// (<spellName>), variable placeholders (@Vars@), and icon references
    /// (%i:scaleCrit%). All three have to go or the text reads as garbage.
    private static func stripMarkup(_ text: String) -> String {
        text
            .replacingOccurrences(of: "<br>", with: " ")
            .replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
            .replacingOccurrences(of: "%i:[A-Za-z0-9_]+%", with: "", options: .regularExpression)
            .replacingOccurrences(of: "@[A-Za-z0-9_.*]+@", with: "?", options: .regularExpression)
            .replacingOccurrences(of: " +", with: " ", options: .regularExpression)
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private struct AugmentResponse: Decodable {
        let augments: [Entry]

        struct Entry: Decodable {
            let id: Int
            let name: String
            let desc: String?
            let rarity: Int?
            let iconSmall: String?
            let iconLarge: String?
        }
    }
}
