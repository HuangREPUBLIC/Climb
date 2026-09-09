import Foundation

actor DataDragonService {
    static let shared = DataDragonService()

    private static let fallbackVersion = "14.24.1"

    private var cachedVersion: String?

    func currentVersion() async -> String {
        if let cachedVersion { return cachedVersion }

        guard let url = URL(string: "https://ddragon.leagueoflegends.com/api/versions.json") else {
            return Self.fallbackVersion
        }

        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let versions = try JSONDecoder().decode([String].self, from: data)
            let version = versions.first ?? Self.fallbackVersion
            cachedVersion = version
            return version
        } catch {
            return Self.fallbackVersion
        }
    }

    func championIconURL(for championName: String) async -> URL? {
        let version = await currentVersion()
        let id = await resolvedChampionID(for: championName)
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/\(version)/img/champion/\(id).png")
    }

    /// Champion asset IDs are case-sensitive and Riot is not internally
    /// consistent about them: Match-V5 reports Fiddlesticks as "FiddleSticks"
    /// (capital S), which 403s against Data Dragon. Rather than hard-coding
    /// that one alias, this matches case-insensitively against Data Dragon's
    /// own champion list, which also covers the nine champions whose asset id
    /// differs from their display name (Wukong -> MonkeyKing, Bel'Veth ->
    /// Belveth, and so on) and any future additions.
    private var championIDsByLowercaseKey: [String: String] = [:]

    private func resolvedChampionID(for championName: String) async -> String {
        let fallback = Self.dataDragonID(for: championName)
        if championIDsByLowercaseKey.isEmpty {
            await loadChampionIDs()
        }
        return championIDsByLowercaseKey[fallback.lowercased()] ?? fallback
    }

    private func loadChampionIDs() async {
        let version = await currentVersion()
        guard let url = URL(string: "https://ddragon.leagueoflegends.com/cdn/\(version)/data/en_US/champion.json") else { return }
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            let response = try JSONDecoder().decode(ChampionDataResponse.self, from: data)
            var mapping: [String: String] = [:]
            for (id, entry) in response.data {
                mapping[id.lowercased()] = id
                // Also key by the stripped display name so "NunuWillump" and
                // "Wukong" resolve to "Nunu" and "MonkeyKing".
                mapping[Self.dataDragonID(for: entry.name).lowercased()] = id
            }
            championIDsByLowercaseKey = mapping
        } catch {
            // Leave empty; resolvedChampionID falls back to the stripped name.
        }
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

    func itemInfo(for itemID: Int) async -> ItemInfo? {
        if itemInfoByID.isEmpty {
            await loadItemData()
        }
        return itemInfoByID[itemID]
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
            // leave empty; itemInfo(for:) just returns nil and callers fall back to icon-only.
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

    /// Name and effect text alongside the icon, so a tapped rune can show
    /// what it actually does.
    struct RuneInfo {
        let id: Int
        let name: String
        let shortDescription: String
        let longDescription: String
        let iconPath: String
    }

    private var runeInfoByID: [Int: RuneInfo] = [:]

    func runeIconURL(for perkOrStyleID: Int) async -> URL? {
        guard perkOrStyleID != 0 else { return nil }
        if runeInfoByID.isEmpty {
            await loadRuneData()
        }
        // Stat shards are absent from runesReforged.json, so they fall through
        // to their own table rather than silently rendering as a blank slot.
        guard let path = runeInfoByID[perkOrStyleID]?.iconPath ?? StatShard.info(for: perkOrStyleID)?.iconPath else {
            return nil
        }
        return URL(string: "https://ddragon.leagueoflegends.com/cdn/img/\(path)")
    }

    func runeInfo(for perkOrStyleID: Int) async -> RuneInfo? {
        if runeInfoByID.isEmpty {
            await loadRuneData()
        }
        if let rune = runeInfoByID[perkOrStyleID] { return rune }
        // Same fallback as the icon lookup, so tapping a shard opens a detail
        // sheet with a name instead of an endless spinner.
        guard let shard = StatShard.info(for: perkOrStyleID) else { return nil }
        return RuneInfo(
            id: perkOrStyleID,
            name: shard.name,
            shortDescription: shard.effect,
            longDescription: shard.effect,
            iconPath: shard.iconPath
        )
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
                mapping[tree.id] = RuneInfo(
                    id: tree.id,
                    name: tree.name,
                    shortDescription: "",
                    longDescription: "",
                    iconPath: tree.icon
                )
                for slot in tree.slots {
                    for rune in slot.runes {
                        mapping[rune.id] = RuneInfo(
                            id: rune.id,
                            name: rune.name,
                            shortDescription: Self.stripHTML(rune.shortDesc ?? ""),
                            longDescription: Self.stripHTML(rune.longDesc ?? rune.shortDesc ?? ""),
                            iconPath: rune.icon
                        )
                    }
                }
            }
            runeInfoByID = mapping
        } catch {
            // leave empty; runeIconURL(for:) just returns nil and the header skips the icon.
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

    /// Data Dragon champion asset IDs strip spaces, apostrophes, and other
    /// punctuation from the display name (e.g. "Kai'Sa" -> "KaiSa",
    /// "Lee Sin" -> "LeeSin"). Real Match-V5 responses already give us the
    /// exact ID, so this only matters for hand-written mock data.
    private static func dataDragonID(for championName: String) -> String {
        let stripped = championName.filter { $0.isLetter || $0.isNumber }
        // Casing fixes for names Riot's match data spells differently from its
        // own asset IDs. championIconURL resolves these dynamically; this table
        // exists for splashArtURL, which is synchronous and can't await the
        // champion list. Verified against Data Dragon: "FiddleSticks" 403s,
        // "Fiddlesticks" is 200.
        let knownCasingFixes: [String: String] = [
            "fiddlesticks": "Fiddlesticks"
        ]
        return knownCasingFixes[stripped.lowercased()] ?? stripped
    }

    /// Summoner spell IDs are stable across patches; mapped by hand since
    /// fetching summoner.json just to resolve ~11 well-known IDs isn't worth
    /// the extra request.
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
