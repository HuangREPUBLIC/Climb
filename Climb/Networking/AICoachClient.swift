import Foundation

/// Talks to Gemini's OpenAI-compatible Chat Completions endpoint
/// (generativelanguage.googleapis.com/v1beta/openai) — chosen because
/// Google AI Studio issues free API keys with no credit card, and this
/// compatibility layer means the request/response shape matches the
/// Chat Completions API the proposal originally assumed for OpenAI.
/// Conversation history is sent in full each call since the API is
/// stateless — CoachService is what persists it between launches.
actor AICoachClient {
    static let shared = AICoachClient()

    private let session = URLSession.shared
    private let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
    /// Best first, then a lighter model with a far larger free allowance.
    /// 3.6-flash's free tier is 20 requests a day (verified from its 429), and
    /// an auto-generated review per game spends that by lunchtime; 3.1-flash-lite
    /// answers the same prompt in ~2s. gemini-2.5-flash 404s for new keys.
    private let models = ["gemini-3.6-flash", "gemini-3.1-flash-lite"]

    func send(systemPrompt: String, history: [ChatMessage], newUserMessage: String) async throws -> String {
        let apiKey = APIKeys.gemini
        guard !apiKey.isEmpty else {
            throw AICoachError.missingAPIKey
        }

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for message in history {
            messages.append(["role": message.role == .player ? "user" : "assistant", "content": message.text])
        }
        messages.append(["role": "user", "content": newUserMessage])

        let data = try await perform(messages: messages, apiKey: apiKey)

        do {
            let decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
            guard let text = decoded.choices.first?.message.content else {
                throw AICoachError.emptyResponse
            }
            return text
        } catch let error as AICoachError {
            throw error
        } catch {
            throw AICoachError.decoding(error)
        }
    }

    /// Walks down `models` while Gemini says "not now" or "not this model":
    /// 429 (quota spent), 503 (high demand), 404 (model retired, as 2.5-flash
    /// was). Anything else — a bad key, a bad request — is a real failure.
    private func perform(messages: [[String: String]], apiKey: String) async throws -> Data {
        var lastCode = 0
        for model in models {
            var request = URLRequest(url: endpoint)
            request.httpMethod = "POST"
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try? JSONSerialization.data(withJSONObject: ["model": model, "messages": messages])

            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw AICoachError.network(error)
            }
            lastCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(lastCode) { return data }
            guard [429, 503, 404].contains(lastCode) else { break }
        }
        throw AICoachError.requestFailed(lastCode)
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }
}
