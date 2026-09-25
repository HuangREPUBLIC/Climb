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
    /// gemini-2.5-flash now 404s for new keys ("no longer available to new
    /// users"), which is what broke the coach. Verified 3.6-flash returns 200
    /// with this key.
    private let model = "gemini-3.6-flash"

    func send(systemPrompt: String, history: [ChatMessage], newUserMessage: String) async throws -> String {
        guard !Secrets.geminiAPIKey.isEmpty else {
            throw AICoachError.missingAPIKey
        }

        var messages: [[String: String]] = [["role": "system", "content": systemPrompt]]
        for message in history {
            messages.append(["role": message.role == .player ? "user" : "assistant", "content": message.text])
        }
        messages.append(["role": "user", "content": newUserMessage])

        let body: [String: Any] = [
            "model": model,
            "messages": messages
        ]

        var request = URLRequest(url: endpoint)
        request.httpMethod = "POST"
        request.setValue("Bearer \(Secrets.geminiAPIKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body)

        let data = try await perform(request)

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

    /// Gemini's free tier answers 503 ("high demand") or 429 in bursts that
    /// clear within seconds, so one delayed retry turns most of those failures
    /// into a normal reply.
    private func perform(_ request: URLRequest) async throws -> Data {
        for attempt in 0..<2 {
            let data: Data
            let response: URLResponse
            do {
                (data, response) = try await session.data(for: request)
            } catch {
                throw AICoachError.network(error)
            }
            let code = (response as? HTTPURLResponse)?.statusCode ?? 0
            if (200..<300).contains(code) { return data }
            if attempt == 0, code == 503 || code == 429 {
                try await Task.sleep(for: .seconds(2))
                continue
            }
            throw AICoachError.requestFailed(code)
        }
        throw AICoachError.requestFailed(0)
    }

    private struct ChatCompletionResponse: Decodable {
        struct Choice: Decodable {
            struct Message: Decodable { let content: String }
            let message: Message
        }
        let choices: [Choice]
    }
}
