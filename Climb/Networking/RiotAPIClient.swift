import Foundation

actor RiotAPIClient {
    static let shared = RiotAPIClient()

    private let session = URLSession.shared

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
        guard let url = URL(string: "https://\(region.rawValue).api.riotgames.com/lol/match/v5/matches/by-puuid/\(puuid)/ids?start=\(start)&count=\(min(count, 100))") else {
            throw RiotAPIError.unexpectedStatus(0)
        }
        return try await get(url)
    }

    func fetchMatch(matchID: String, region: RiotRegion) async throws -> RiotMatchResponse {
        guard let url = URL(string: "https://\(region.rawValue).api.riotgames.com/lol/match/v5/matches/\(matchID)") else {
            throw RiotAPIError.unexpectedStatus(0)
        }
        return try await get(url)
    }

    func fetchMatchTimeline(matchID: String, region: RiotRegion) async throws -> RiotMatchTimelineResponse {
        guard let url = URL(string: "https://\(region.rawValue).api.riotgames.com/lol/match/v5/matches/\(matchID)/timeline") else {
            throw RiotAPIError.unexpectedStatus(0)
        }
        return try await get(url)
    }

    func fetchSummoner(puuid: String, platform: RiotPlatform) async throws -> RiotSummonerResponse {
        guard let url = URL(string: "https://\(platform.rawValue).api.riotgames.com/lol/summoner/v4/summoners/by-puuid/\(puuid)") else {
            throw RiotAPIError.unexpectedStatus(0)
        }
        return try await get(url)
    }

    func fetchLeagueEntries(puuid: String, platform: RiotPlatform) async throws -> [RiotLeagueEntry] {
        guard let url = URL(string: "https://\(platform.rawValue).api.riotgames.com/lol/league/v4/entries/by-puuid/\(puuid)") else {
            throw RiotAPIError.unexpectedStatus(0)
        }
        return try await get(url)
    }

    func fetchRecentTFTMatchIDs(puuid: String, region: RiotRegion, count: Int = 20) async throws -> [String] {
        guard let url = URL(string: "https://\(region.rawValue).api.riotgames.com/tft/match/v1/matches/by-puuid/\(puuid)/ids?count=\(count)") else {
            throw RiotAPIError.unexpectedStatus(0)
        }
        return try await get(url)
    }

    func fetchTFTMatch(matchID: String, region: RiotRegion) async throws -> RiotTFTMatchResponse {
        guard let url = URL(string: "https://\(region.rawValue).api.riotgames.com/tft/match/v1/matches/\(matchID)") else {
            throw RiotAPIError.unexpectedStatus(0)
        }
        return try await get(url, decoder: Self.snakeCaseDecoder)
    }

    private static let snakeCaseDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return decoder
    }()

    private func get<T: Decodable>(_ url: URL, decoder: JSONDecoder = JSONDecoder()) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue(Secrets.riotAPIKey, forHTTPHeaderField: "X-Riot-Token")

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
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
