import Foundation

enum RiotAPIError: LocalizedError {
    case invalidRiotID
    case rateLimited
    case unauthorized
    case network(Error)
    case decoding(Error)
    case unexpectedStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidRiotID:
            return "That Riot ID couldn't be found. Double-check the name, tagline, and region."
        case .rateLimited:
            return "Riot's API is rate-limiting requests right now. Try again in a minute."
        case .unauthorized:
            return "The Riot API key is missing, invalid, or expired. Personal keys expire after 24 hours."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .decoding:
            return "Couldn't read Riot's response."
        case .unexpectedStatus(let code):
            return "Riot API returned an unexpected status (\(code))."
        }
    }
}
