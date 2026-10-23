import Foundation

actor DataDragonService {
    static let shared = DataDragonService()

    private static let fallbackVersion = "14.24.1"

    // Actors reenter across `await`: concurrent callers share this one task (kept after it
    // finishes), so versions.json is fetched once per launch.
    private var versionTask: Task<String, Never>?

    func currentVersion() async -> String {
        let task = versionTask ?? Task {
            do {
                let url = URL(string: "https://ddragon.leagueoflegends.com/api/versions.json")!
                let (data, _) = try await URLSession.shared.data(from: url)
                let versions = try JSONDecoder().decode([String].self, from: data)
                return versions.first ?? Self.fallbackVersion
            } catch {
                return Self.fallbackVersion
            }
        }
        versionTask = task
        return await task.value
    }

    func championIconURL(for championName: String) async -> URL? {
        let version = await currentVersion()
        let id = await resolvedChampionID(for: championName)
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/\(version)/img/champion/\(id).png")
    }

    /// Asset ids are case-sensitive and Match-V5 disagrees ("FiddleSticks" 403s); a few also
    /// differ from the display name (Wukong -> MonkeyKing). Matching case-insensitively against
    /// Data Dragon's own champion list resolves both.
    private var championIDsByLowercaseKey: [String: String] = [:]
    // Same reentrancy guard as versionTask: one champion.json (~700KB) fetch, not one per icon.
    private var championIDsTask: Task<Void, Never>?

    /// Any spelling (Riot "MonkeyKing", op.gg "Wukong") to its Data Dragon id, so sources compare.
    func resolvedChampionID(for championName: String) async -> String {
        let fallback = Self.dataDragonID(for: championName)
        if championIDsByLowercaseKey.isEmpty {
            await loadChampionIDs()
        }
        return championIDsByLowercaseKey[fallback.lowercased()] ?? fallback
    }

    private func loadChampionIDs() async {
        if let championIDsTask {
            await championIDsTask.value
            return
        }

        let task = Task<Void, Never> {
            let version = await currentVersion()
            guard let url = URL(string: "https://ddragon.leagueoflegends.com/cdn/\(version)/data/en_US/champion.json") else { return }
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                let response = try JSONDecoder().decode(ChampionDataResponse.self, from: data)
                var mapping: [String: String] = [:]
                for (id, entry) in response.data {
                    mapping[id.lowercased()] = id
                    // Also key by the stripped display name ("Wukong" -> "MonkeyKing").
                    mapping[Self.dataDragonID(for: entry.name).lowercased()] = id
                }
                self.championIDsByLowercaseKey = mapping
            } catch {
                // Leave empty; resolvedChampionID falls back to the stripped name.
            }
        }
        championIDsTask = task
        await task.value
        championIDsTask = nil
    }

    private struct ChampionDataResponse: Decodable {
        let data: [String: Entry]
        struct Entry: Decodable { let name: String }
    }

    func profileIconURL(for profileIconID: Int) async -> URL? {
        let version = await currentVersion()
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/\(version)/img/profileicon/\(profileIconID).png")
    }

    nonisolated func splashArtURL(for championName: String) -> URL? {
        let id = Self.dataDragonID(for: championName)
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/img/champion/splash/\(id)_0.jpg")
    }

    /// Portrait art (face near the top) for narrow frames, where the landscape splash crops badly.
    nonisolated func loadingArtURL(for championName: String) -> URL? {
        let id = Self.dataDragonID(for: championName)
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/img/champion/loading/\(id)_0.jpg")
    }

    func itemIconURL(for itemID: Int) async -> URL? {
        guard itemID != 0 else { return nil }
        let version = await currentVersion()
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/\(version)/img/item/\(itemID).png")
    }

    struct ItemInfo {
        let name: String
        let plainDescription: String
        let totalCost: Int
    }

    private var itemInfoByID: [Int: ItemInfo] = [:]
    // Same reentrancy guard as championIDsTask: every match card prices its build at launch. Kept
    // after finishing so a failed load isn't retried by every card (icons only until relaunch).
    private var itemDataTask: Task<Void, Never>?

    func itemInfo(for itemID: Int) async -> ItemInfo? {
        if itemDataTask == nil { itemDataTask = Task { await loadItemData() } }
        await itemDataTask?.value
        return itemInfoByID[itemID]
    }

    /// Total gold cost of each item, in one hop instead of one per item.
    func itemCosts(_ itemIDs: [Int]) async -> [Int: Int] {
        _ = await itemInfo(for: 0)
        return Dictionary(itemIDs.map { ($0, itemInfoByID[$0]?.totalCost ?? 0) }, uniquingKeysWith: { a, _ in a })
    }

    private func loadItemData() async {
        let version = await currentVersion()
        guard let url = URL(string: "https://ddragon.leagueoflegends.com/cdn/\(version)/data/en_US/item.json") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ItemDataResponse.self, from: data)
            var mapping: [Int: ItemInfo] = [:]
            for (key, entry) in response.data {
                guard let id = Int(key) else { continue }
                mapping[id] = ItemInfo(
                    name: entry.name,
                    plainDescription: Self.stripHTML(entry.plaintext ?? entry.description ?? ""),
                    totalCost: entry.gold.total
                )
            }
            itemInfoByID = mapping
        } catch {
            // Leave empty: itemInfo(for:) returns nil and callers show icons only.
        }
    }

    private static func stripHTML(_ string: String) -> String {
        string.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
    }

    private struct ItemDataResponse: Decodable {
        let data: [String: Entry]
        struct Entry: Decodable {
            let name: String
            let description: String?
            let plaintext: String?
            let gold: Gold
            struct Gold: Decodable { let total: Int }
        }
    }

    struct RuneInfo {
        let name: String
        let longDescription: String
        let iconPath: String
    }

    private var runeInfoByID: [Int: RuneInfo] = [:]

    func runeIconURL(for perkOrStyleID: Int) async -> URL? {
        guard perkOrStyleID != 0, let path = await runeInfo(for: perkOrStyleID)?.iconPath else { return nil }
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/img/\(path)")
    }

    func runeInfo(for perkOrStyleID: Int) async -> RuneInfo? {
        if runeInfoByID.isEmpty {
            await loadRuneData()
        }
        if let rune = runeInfoByID[perkOrStyleID] { return rune }
        // Stat shards aren't in runesReforged.json; their own table keeps the icon from going blank
        // and the detail sheet from spinning forever.
        guard let shard = StatShard.info(for: perkOrStyleID) else { return nil }
        return RuneInfo(name: shard.name, longDescription: shard.effect, iconPath: shard.iconPath)
    }

    private func loadRuneData() async {
        let version = await currentVersion()
        guard let url = URL(string: "https://ddragon.leagueoflegends.com/cdn/\(version)/data/en_US/runesReforged.json") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let trees = try JSONDecoder().decode([RuneTree].self, from: data)
            var mapping: [Int: RuneInfo] = [:]
            for tree in trees {
                // Tree entries (Precision, Domination, …) have no description.
                mapping[tree.id] = RuneInfo(name: tree.name, longDescription: "", iconPath: tree.icon)
                for slot in tree.slots {
                    for rune in slot.runes {
                        mapping[rune.id] = RuneInfo(
                            name: rune.name,
                            longDescription: Self.stripHTML(rune.longDesc ?? rune.shortDesc ?? ""),
                            iconPath: rune.icon
                        )
                    }
                }
            }
            runeInfoByID = mapping
        } catch {
            // Leave empty: runeIconURL(for:) returns nil and the header skips the icon.
        }
    }

    private struct RuneTree: Decodable {
        let id: Int
        let name: String
        let icon: String
        let slots: [Slot]
        struct Slot: Decodable {
            let runes: [Rune]
        }
        struct Rune: Decodable {
            let id: Int
            let name: String
            let icon: String
            let shortDesc: String?
            let longDesc: String?
        }
    }

    func summonerSpellIconURL(for spellID: Int) async -> URL? {
        guard let file = Self.summonerSpellFiles[spellID] else { return nil }
        let version = await currentVersion()
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/\(version)/img/spell/\(file).png")
    }

    /// Data Dragon ids strip spaces and punctuation from the display name ("Kai'Sa" -> "KaiSa").
    private static func dataDragonID(for championName: String) -> String {
        let stripped = championName.filter { $0.isLetter || $0.isNumber }
        // Match-V5 spells it "FiddleSticks", which 403s on Data Dragon. The champion list fixes it
        // dynamically; this is for the synchronous splashArtURL, which can't await that list.
        return stripped.lowercased() == "fiddlesticks" ? "Fiddlesticks" : stripped
    }

    /// Mapped by hand: ids are stable across patches, so summoner.json isn't worth a request.
    private static let summonerSpellFiles: [Int: String] = [
        1: "SummonerBoost",
        3: "SummonerExhaust",
        4: "SummonerFlash",
        6: "SummonerHaste",
        7: "SummonerHeal",
        11: "SummonerSmite",
        12: "SummonerTeleport",
        13: "SummonerMana",
        14: "SummonerDot",
        21: "SummonerBarrier",
        32: "SummonerSnowball"
    ]
}
