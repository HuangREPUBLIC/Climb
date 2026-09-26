import Foundation

/// op.gg's public MCP server (no key needed): champion tiers per lane and
/// per-champion builds, runes, skills and counters — the meta data Riot's
/// own API doesn't expose.
actor OPGGClient {
    static let shared = OPGGClient()

    private let endpoint = URL(string: "https://mcp-api.op.gg/mcp")!
    /// Meta shifts by patch, not by minute; six hours keeps tab switches free.
    private var cache: [String: (fetched: Date, json: Data)] = [:]

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    /// Tier list for one lane, best first.
    func laneMeta(_ position: OPGGPosition) async throws -> [MetaChampion] {
        let decoded: LaneMetaResponse = try await fetch("lol_list_lane_meta_champions", [
            "position": position.rawValue,
            "lang": "en_US",
            "desired_output_fields": ["data.positions.\(position.rawValue)[].{champion,tier,rank,win_rate,pick_rate,ban_rate}"]
        ])
        return (decoded.data.positions[position.rawValue] ?? []).sorted { $0.rank < $1.rank }
    }

    func analysis(champion: String, position: OPGGPosition) async throws -> ChampionAnalysis {
        let decoded: ChampionAnalysisResponse = try await fetch("lol_get_champion_analysis", [
            "game_mode": "ranked",
            "champion": Self.opggName(champion),
            "position": position.rawValue,
            "lang": "en_US",
            "desired_output_fields": [
                "data.summary.average_stats.{win_rate,pick_rate,ban_rate,tier,rank}",
                "data.starter_items.{ids[],play,win}",
                "data.core_items.{ids[],play,win}",
                "data.boots.{ids[],play,win}",
                "data.summoner_spells.{ids[],play,win}",
                "data.runes.{primary_page_id,primary_rune_ids[],secondary_page_id,secondary_rune_ids[],stat_mod_ids[],play,win}",
                "data.skills.{order[],play,win}",
                "data.strong_counters[].{champion_name,play,my_win_rate}",
                "data.weak_counters[].{champion_name,play,my_win_rate}"
            ]
        ])
        return decoded.data
    }

    /// The lane tier list's grade for one champion — the same number the
    /// Champions list shows, so a champion is never T1 there and T2 here.
    func tier(of champion: String, position: OPGGPosition) async -> Int? {
        let name = Self.opggName(champion)
        return try? await laneMeta(position).first { Self.opggName($0.champion) == name }?.tier
    }

    /// op.gg takes UPPER_SNAKE_CASE and is lenient about the separators, so
    /// "Kai'Sa", "Dr. Mundo" and "Nunu & Willump" all map by splitting on
    /// anything that isn't a letter or digit.
    static func opggName(_ champion: String) -> String {
        champion.uppercased()
            .split { !$0.isLetter && !$0.isNumber }
            .joined(separator: "_")
    }

    private static let decoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    /// Cached only once the reply has decoded, so a bad reply isn't served
    /// again for six hours and "Try again" really tries again.
    private func fetch<T: Decodable>(_ tool: String, _ arguments: [String: Any]) async throws -> T {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "tools/call",
            "params": ["name": tool, "arguments": arguments]
        ]
        let bodyData = try JSONSerialization.data(withJSONObject: body, options: .sortedKeys)
        let cacheKey = String(decoding: bodyData, as: UTF8.self)
        if let hit = cache[cacheKey], hit.fetched.timeIntervalSinceNow > -6 * 60 * 60,
           let value = try? Self.decoder.decode(T.self, from: hit.json) {
            return value
        }

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
        request.httpBody = bodyData
        // The coach waits on this too; a stalled op.gg mustn't hold a review
        // for URLSession's default minute.
        request.timeoutInterval = 10

        let (data, _) = try await URLSession.shared.data(for: request)
        let envelope = try JSONDecoder().decode(Envelope.self, from: data)
        if let error = envelope.error { throw Failure(message: error.message) }
        guard let text = envelope.result?.content.first?.text, envelope.result?.isError != true else {
            throw Failure(message: envelope.result?.content.first?.text ?? "op.gg returned nothing.")
        }
        let object = try OPGGNotation.parse(text)
        // JSONSerialization raises an uncatchable exception on anything that
        // isn't an object or array, or on inf/NaN — check first.
        guard JSONSerialization.isValidJSONObject(object) else {
            throw Failure(message: "op.gg sent a reply the app couldn't read.")
        }
        let json = try JSONSerialization.data(withJSONObject: object)
        let value = try Self.decoder.decode(T.self, from: json)
        cache[cacheKey] = (.now, json)
        return value
    }

    private struct Envelope: Decodable {
        struct Result: Decodable {
            struct Content: Decodable { let text: String? }
            let content: [Content]
            let isError: Bool?
        }
        struct RPCError: Decodable { let message: String }
        let result: Result?
        let error: RPCError?
    }
}

nonisolated enum OPGGPosition: String, CaseIterable, Identifiable {
    case top, jungle, mid, adc, support

    var id: String { rawValue }
    var title: String { self == .adc ? "ADC" : rawValue.capitalized }

    /// From the app's own role names ("Top", "ADC"…).
    init?(role: String) {
        self.init(rawValue: role.lowercased())
    }
}

nonisolated struct MetaChampion: Decodable, Identifiable {
    let champion: String
    /// op.gg's grade: 0 is "OP", then 1 (best) to 5. Nil if it sent none.
    let tier: Int?
    let rank: Int
    let winRate: Double
    let pickRate: Double
    let banRate: Double
    var id: String { champion }

    /// Lenient: one champion with a missing number mustn't sink the list.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        champion = try c.decode(String.self, forKey: .champion)
        tier = try? c.decodeIfPresent(Int.self, forKey: .tier)
        rank = (try? c.decodeIfPresent(Int.self, forKey: .rank)) ?? Int.max
        winRate = (try? c.decodeIfPresent(Double.self, forKey: .winRate)) ?? 0
        pickRate = (try? c.decodeIfPresent(Double.self, forKey: .pickRate)) ?? 0
        banRate = (try? c.decodeIfPresent(Double.self, forKey: .banRate)) ?? 0
    }

    private enum CodingKeys: String, CodingKey {
        case champion, tier, rank, winRate, pickRate, banRate
    }
}

nonisolated struct ChampionAnalysis: Decodable {
    struct Stats: Decodable {
        let winRate: Double
        let pickRate: Double
        let banRate: Double
        let tier: Int
        let rank: Int
    }
    struct Summary: Decodable { let averageStats: Stats }
    /// A build step: items, boots or summoner spells, with how it performs.
    struct Pick: Decodable {
        let ids: [Int]
        let play: Int
        let win: Int
        var winRate: Double { play > 0 ? Double(win) / Double(play) : 0 }
    }
    struct Runes: Decodable {
        let primaryPageId: Int
        let primaryRuneIds: [Int]
        let secondaryPageId: Int
        let secondaryRuneIds: [Int]
        let statModIds: [Int]
        let play: Int
        let win: Int
    }
    struct Skills: Decodable {
        let order: [String]
        let play: Int
        let win: Int
    }
    struct Counter: Decodable, Identifiable {
        let championName: String
        let play: Int
        /// This champion's win rate in the matchup.
        let myWinRate: Double
        var id: String { championName }
    }

    let summary: Summary?
    let starterItems: Pick?
    let coreItems: Pick?
    let boots: Pick?
    let summonerSpells: Pick?
    let runes: Runes?
    let skills: Skills?
    let strongCounters: [Counter]?
    let weakCounters: [Counter]?

    /// Section by section: a malformed rune page drops the runes card, not
    /// the whole screen.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        summary = try? c.decodeIfPresent(Summary.self, forKey: .summary)
        starterItems = try? c.decodeIfPresent(Pick.self, forKey: .starterItems)
        coreItems = try? c.decodeIfPresent(Pick.self, forKey: .coreItems)
        boots = try? c.decodeIfPresent(Pick.self, forKey: .boots)
        summonerSpells = try? c.decodeIfPresent(Pick.self, forKey: .summonerSpells)
        runes = try? c.decodeIfPresent(Runes.self, forKey: .runes)
        skills = try? c.decodeIfPresent(Skills.self, forKey: .skills)
        strongCounters = try? c.decodeIfPresent([Counter].self, forKey: .strongCounters)
        weakCounters = try? c.decodeIfPresent([Counter].self, forKey: .weakCounters)
    }

    private enum CodingKeys: String, CodingKey {
        case summary, starterItems, coreItems, boots, summonerSpells, runes, skills, strongCounters, weakCounters
    }
}

nonisolated private struct LaneMetaResponse: Decodable {
    struct Payload: Decodable { let positions: [String: [MetaChampion]] }
    let data: Payload
}

nonisolated private struct ChampionAnalysisResponse: Decodable {
    let data: ChampionAnalysis
}

/// op.gg's MCP answers in a compact notation meant for LLMs, not JSON:
///
///     class Top: champion,win_rate
///     LolListLaneMetaChampions(Data(Positions([Top("Malphite",0.51)])))
///
/// Each `class` line gives a type's field order; calls are positional. This
/// turns it into plain JSON objects so `Decodable` can take it from there.
nonisolated enum OPGGNotation {
    struct ParseError: Error {}

    static func parse(_ text: String) throws -> Any {
        var fieldsByClass: [String: [String]] = [:]
        var body: [Substring] = []
        for line in text.split(whereSeparator: \.isNewline) {
            if line.hasPrefix("class "), let colon = line.firstIndex(of: ":") {
                let name = line[line.index(line.startIndex, offsetBy: 6)..<colon].trimmingCharacters(in: .whitespaces)
                fieldsByClass[name] = line[line.index(after: colon)...]
                    .split(separator: ",")
                    .map { $0.trimmingCharacters(in: .whitespaces) }
            } else {
                body.append(line)
            }
        }
        var parser = Parser(chars: Array(body.joined(separator: "\n")), fieldsByClass: fieldsByClass)
        return try parser.value()
    }

    private struct Parser {
        let chars: [Character]
        let fieldsByClass: [String: [String]]
        var index = 0

        mutating func value() throws -> Any {
            skipWhitespace()
            guard index < chars.count else { throw ParseError() }
            switch chars[index] {
            case "[": return try sequence(closing: "]")
            case "\"": return try string()
            case "-", "0"..."9": return number()
            default: break
            }
            let start = index
            while index < chars.count, chars[index].isLetter || chars[index].isNumber || chars[index] == "_" { index += 1 }
            guard index > start else { throw ParseError() }
            let name = String(chars[start..<index])
            skipWhitespace()
            if index < chars.count, chars[index] == "(" {
                let arguments = try sequence(closing: ")")
                let fields = fieldsByClass[name] ?? []
                return Dictionary(zip(fields, arguments), uniquingKeysWith: { first, _ in first })
            }
            switch name {
            case "True", "true": return true
            case "False", "false": return false
            default: return NSNull()
            }
        }

        mutating func sequence(closing: Character) throws -> [Any] {
            index += 1
            var items: [Any] = []
            skipWhitespace()
            if index < chars.count, chars[index] == closing {
                index += 1
                return items
            }
            while true {
                items.append(try value())
                skipWhitespace()
                guard index < chars.count else { throw ParseError() }
                if chars[index] == "," {
                    index += 1
                } else if chars[index] == closing {
                    index += 1
                    return items
                } else {
                    throw ParseError()
                }
            }
        }

        mutating func string() throws -> String {
            index += 1
            var out = ""
            while index < chars.count {
                let char = chars[index]
                index += 1
                if char == "\"" { return out }
                guard char == "\\", index < chars.count else {
                    out.append(char)
                    continue
                }
                let escaped = chars[index]
                index += 1
                switch escaped {
                case "n": out.append("\n")
                case "t": out.append("\t")
                case "u":
                    let hex = String(chars[index..<min(index + 4, chars.count)])
                    index += 4
                    if let code = UInt32(hex, radix: 16), let scalar = Unicode.Scalar(code) {
                        out.unicodeScalars.append(scalar)
                    }
                default: out.append(escaped)
                }
            }
            throw ParseError()
        }

        mutating func number() -> Any {
            let start = index
            while index < chars.count, "-+.eE0123456789".contains(chars[index]) { index += 1 }
            let text = String(chars[start..<index])
            if let integer = Int(text) { return integer }
            return Double(text) ?? 0
        }

        mutating func skipWhitespace() {
            while index < chars.count, chars[index].isWhitespace { index += 1 }
        }
    }

    #if DEBUG
    /// Runs on every debug launch; fails loudly if the parser stops mapping
    /// op.gg's notation (reused class names, nested lists, escaped quotes).
    static func selfCheck() {
        let sample = """
        class Root: data
        class Data: name,picks,rate,note
        class Pick: ids,win

        Root(Data("Kai'Sa",[Pick([3074,3078],12),Pick([],0)],-0.5,"say \\"hi\\""))
        """
        let root = try? parse(sample) as? [String: Any]
        let data = root?["data"] as? [String: Any]
        let picks = data?["picks"] as? [[String: Any]]
        assert(data?["name"] as? String == "Kai'Sa", "name: \(String(describing: data))")
        assert(picks?.count == 2 && picks?.first?["ids"] as? [Int] == [3074, 3078], "picks: \(String(describing: picks))")
        assert(data?["rate"] as? Double == -0.5 && data?["note"] as? String == "say \"hi\"", "scalars: \(String(describing: data))")
        assert(OPGGClient.opggName("Nunu & Willump") == "NUNU_WILLUMP" && OPGGClient.opggName("Kai'Sa") == "KAI_SA")
    }
    #endif
}
