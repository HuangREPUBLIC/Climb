import Foundation

enum AICoachError: LocalizedError {
    case missingAPIKey
    case network(Error)
    case requestFailed(Int)
    case emptyResponse
    case decoding(Error)
    case notYourGame

    var errorDescription: String? {
        switch self {
        case .missingAPIKey:
            return "No LLM API key configured. Add a free key from aistudio.google.com/apikey to Secrets.geminiAPIKey."
        case .network(let error):
            return "Network error: \(error.localizedDescription)"
        case .requestFailed(let code):
            return "The AI coach request failed (status \(code))."
        case .emptyResponse:
            return "The AI coach didn't return a response."
        case .decoding:
            return "Couldn't read the AI coach's response."
        case .notYourGame:
            return "The AI coach only reviews your own games."
        }
    }
}
