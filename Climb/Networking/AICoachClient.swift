import Foundation

/// Gemini's OpenAI-compatible Chat Completions endpoint, chosen because AI Studio issues free keys
/// with no card. The API is stateless, so history is sent in full each call; CoachService persists it.
actor AICoachClient {
    static let shared = AICoachClient()

    private let endpoint = URL(string: "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")!
    /// Best first, then a lighter model with a far larger free allowance: 3.6-flash's free tier is
    /// 20 requests a day, which per-game reviews spend by lunchtime. 2.5-flash 404s for new keys.
    private let models = ["gemini-3.6-flash", "gemini-3.1-flash-lite"]

    func send(systemPrompt: String, history: [ChatMessage], newUserMessage: String) async throws -> String {
        let apiKey = APIKeys.gemini
        guard !apiKey.isEmpty else {
            throw Failure(message: "No LLM API key configured. Add a free key from aistudio.google.com/apikey under Riot Account → API Keys.")
        }

        let messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
            + history.map { ["role": $0.role == .player ? "user" : "assistant", "content": $0.text] }
            + [["role": "user", "content": newUserMessage]]

        let data = try await perform(messages: messages, apiKey: apiKey)

        let decoded: ChatCompletionResponse
        do {
            decoded = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)
        } catch {
            throw Failure(message: "Couldn't read the AI coach's response.")
        }
        guard let text = decoded.choices.first?.message.content else {
            throw Failure(message: "The AI coach didn't return a response.")
        }
        return text
    }

    /// Next model on 429 (quota), 503 (busy) or 404 (retired); any other status is a real failure.
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
                (data, response) = try await URLSession.shared.data(for: request)
            } catch {
                throw Failure(message: "Network error: \(error.localizedDescription)")
            }
            lastCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(lastCode) { return data }
            guard [429, 503, 404].contains(lastCode) else { break }
        }
        throw Failure(message: "The AI coach request failed (status \(lastCode)).")
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }
}
