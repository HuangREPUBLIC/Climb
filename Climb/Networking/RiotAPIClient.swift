import Foundation

actor RiotAPIClient {
    static let shared = RiotAPIClient()

    func resolvePUUID(gameName: String, tagLine: String, region: RiotRegion) async throws -> String {
        guard
            let encodedName = gameName.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let encodedTag = tagLine.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed),
            let url = URL(string: "https://\(region.rawValue).api.riotgames.com/riot/account/v1/accounts/by-riot-id/\(encodedName)/\(encodedTag)")
        else {
            throw RiotAPIError.invalidRiotID
        }
        let response: RiotAccountResponse = try await get(url)
        return response.puuid
    }

    /// Riot caps `count` at 100 (it 400s on anything larger).
    func fetchRecentMatchIDs(puuid: String, region: RiotRegion, start: Int = 0, count: Int = 20) async throws -> [String] {
        try await get(url(region.rawValue, "/lol/match/v5/matches/by-puuid/\(puuid)/ids?start=\(start)&count=\(min(count, 100))"))
    }

    func fetchMatch(matchID: String, region: RiotRegion) async throws -> RiotMatchResponse {
        try await get(url(region.rawValue, "/lol/match/v5/matches/\(matchID)"))
    }

    func fetchMatchTimeline(matchID: String, region: RiotRegion) async throws -> RiotMatchTimelineResponse {
        try await get(url(region.rawValue, "/lol/match/v5/matches/\(matchID)/timeline"))
    }

    func fetchSummoner(puuid: String, platform: RiotPlatform) async throws -> RiotSummonerResponse {
        try await get(url(platform.rawValue, "/lol/summoner/v4/summoners/by-puuid/\(puuid)"))
    }

    func fetchLeagueEntries(puuid: String, platform: RiotPlatform) async throws -> [RiotLeagueEntry] {
        try await get(url(platform.rawValue, "/lol/league/v4/entries/by-puuid/\(puuid)"))
    }

    /// Another player's current solo rank, looked up on demand — not stored:
    /// rank is always-current, not a property of a historical match. Nil when
    /// unranked or when the lookup failed.
    func soloRank(puuid: String, platform: RiotPlatform) async -> RiotLeagueEntry? {
        try? await fetchLeagueEntries(puuid: puuid, platform: platform).first { $0.queueType == "RANKED_SOLO_5x5" }
    }

    func fetchRecentTFTMatchIDs(puuid: String, region: RiotRegion, count: Int = 20) async throws -> [String] {
        try await get(url(region.rawValue, "/tft/match/v1/matches/by-puuid/\(puuid)/ids?count=\(count)"))
    }

    func fetchTFTMatch(matchID: String, region: RiotRegion) async throws -> RiotTFTMatchResponse {
        try await get(url(region.rawValue, "/tft/match/v1/matches/\(matchID)"), decoder: .snakeCase)
    }

    /// `host` is a regional (`asia`) or platform (`jp1`) routing value.
    private func url(_ host: String, _ path: String) throws -> URL {
        guard let url = URL(string: "https://\(host).api.riotgames.com\(path)") else {
            throw RiotAPIError.unexpectedStatus(0)
        }
        return url
    }

    private func get<T: Decodable>(_ url: URL, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(APIKeys.riot, forHTTPHeaderField: "X-Riot-Token")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch {
            throw RiotAPIError.network(error)
        }

        guard let httpResponse = response as? HTTPURLResponse else {
            throw RiotAPIError.network(URLError(.badServerResponse))
        }

        switch httpResponse.statusCode {
        case 200..<300:
            break
        case 401, 403:
            // Almost always today's personal key having expired — ask for a
            // new one rather than failing every sync quietly.
            await MainActor.run { APIKeyPrompt.shared.riotKeyRejected = true }
            throw RiotAPIError.unauthorized
        case 404:
            throw RiotAPIError.invalidRiotID
        case 429:
            throw RiotAPIError.rateLimited
        default:
            // Surface what Riot actually rejected — a bare status code gives
            // no way to tell a bad parameter from a bad route.
            let body = String(data: data, encoding: .utf8) ?? "<no body>"
            print("[RiotAPI] \(httpResponse.statusCode) for \(url.absoluteString)\n  body: \(body)")
            throw RiotAPIError.unexpectedStatus(httpResponse.statusCode)
        }

        do {
            return try decoder.decode(T.self, from: data)
        } catch {
            throw RiotAPIError.decoding(error)
        }
    }
}

extension JSONDecoder {
    /// TFT-Match-V1 and op.gg both answer in snake_case.
    nonisolated static let snakeCase: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()
}
