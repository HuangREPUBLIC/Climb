import Foundation

/// Mirrors RiotAPIClient's League/TFT methods for VAL-MATCH-V1. Inert until
/// the app's key has VALORANT access — every call will 403 until then. See
/// RiotValorantRegion.swift for why this exists ahead of that access.
actor RiotValorantAPIClient {
    static let shared = RiotValorantAPIClient()

    private let session = URLSession.shared

    func fetchRecentMatchIDs(puuid: String, region: RiotValorantRegion) async throws -> [String] {
        guard let url = URL(string: "https://\(region.rawValue).api.riotgames.com/val/match/v1/matchlists/by-puuid/\(puuid)") else {
            throw RiotAPIError.unexpectedStatus(0)
        }
        let matchlist: MatchlistResponse = try await get(url)
        return matchlist.history.map(\.matchId)
    }

    func fetchMatch(matchID: String, region: RiotValorantRegion) async throws -> RiotValorantMatchResponse {
        guard let url = URL(string: "https://\(region.rawValue).api.riotgames.com/val/match/v1/matches/\(matchID)") else {
            throw RiotAPIError.unexpectedStatus(0)
        }
        return try await get(url)
    }

    private struct MatchlistResponse: Decodable {
        struct Entry: Decodable { let matchId: String }
        let history: [Entry]
    }

    private func get<T: Decodable>(_ url: URL) async throws -> T {
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
            throw RiotAPIError.unexpectedStatus(httpResponse.statusCode)
        }

        do {
            return try JSONDecoder().decode(T.self, from: data)
        } catch {
            throw RiotAPIError.decoding(error)
        }
    }
}
