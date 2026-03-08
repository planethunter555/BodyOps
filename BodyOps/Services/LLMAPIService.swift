import Foundation

// MARK: - Protocol

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

// MARK: - Models

struct LLMMessage: Sendable {
    let role: String
    let content: String
    var imageData: Data?

    init(role: String, content: String, imageData: Data? = nil) {
        self.role = role
        self.content = content
        self.imageData = imageData
    }
}

enum LLMError: Error, Equatable {
    case unauthorized
    case rateLimited
    case serverError
    case networkError
}

// MARK: - Service

final class LLMAPIService: @unchecked Sendable {
    private let session: URLSessionProtocol

    init(session: URLSessionProtocol = URLSession.shared) {
        self.session = session
    }

    func endpointURL(for provider: LLMProvider) -> URL {
        switch provider {
        case .claude:
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai:
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini:
            let model = "gemini-2.0-flash"
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent")!
        }
    }

    func sendMessage(
        messages: [LLMMessage],
        system: String,
        provider: LLMProvider,
        apiKey: String,
        modelName: String = ""
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @Sendable in
                do {
                    var request = URLRequest(url: endpointURL(for: provider))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    applyAuthHeaders(to: &request, provider: provider, apiKey: apiKey)
                    request.httpBody = try buildRequestBody(
                        messages: messages, system: system, provider: provider, modelName: modelName
                    )

                    let (data, response) = try await session.data(for: request)
                    guard let httpResponse = response as? HTTPURLResponse else {
                        continuation.finish(throwing: LLMError.serverError)
                        return
                    }

                    switch httpResponse.statusCode {
                    case 200:
                        let chunks = parseSSEResponse(data: data, provider: provider)
                        for chunk in chunks {
                            continuation.yield(chunk)
                        }
                        continuation.finish()
                    case 401:
                        continuation.finish(throwing: LLMError.unauthorized)
                    case 429:
                        continuation.finish(throwing: LLMError.rateLimited)
                    default:
                        continuation.finish(throwing: LLMError.serverError)
                    }
                } catch is LLMError {
                    continuation.finish(throwing: LLMError.networkError)
                } catch {
                    continuation.finish(throwing: LLMError.networkError)
                }
            }
        }
    }

    func buildRequestBody(
        messages: [LLMMessage],
        system: String,
        provider: LLMProvider,
        modelName: String = "",
        stream: Bool = true
    ) throws -> Data {
        switch provider {
        case .claude:
            return try buildClaudeBody(messages: messages, system: system, modelName: modelName, stream: stream)
        case .openai:
            return try buildOpenAIBody(messages: messages, system: system, modelName: modelName, stream: stream)
        case .gemini:
            return try buildGeminiBody(messages: messages, system: system)
        }
    }

    /// ストリーミング不要な単発リクエスト（PFC推定など）用。
    /// stream: false で送ってシンプルなJSONを1回で受け取るため、SSEパース起因の初回失敗が起きない。
    func sendOnce(
        messages: [LLMMessage],
        system: String,
        provider: LLMProvider,
        apiKey: String,
        modelName: String = ""
    ) async throws -> String {
        var request = URLRequest(url: nonStreamingEndpointURL(for: provider, modelName: modelName))
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        applyAuthHeaders(to: &request, provider: provider, apiKey: apiKey)
        request.httpBody = try buildRequestBody(
            messages: messages, system: system, provider: provider, modelName: modelName, stream: false
        )

        let (data, response) = try await URLSession.shared.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else { throw LLMError.serverError }

        switch httpResponse.statusCode {
        case 200: return try extractResponseText(from: data, provider: provider)
        case 401: throw LLMError.unauthorized
        case 429: throw LLMError.rateLimited
        default:  throw LLMError.serverError
        }
    }

    private func nonStreamingEndpointURL(for provider: LLMProvider, modelName: String) -> URL {
        switch provider {
        case .claude:
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai:
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini:
            let model = modelName.isEmpty ? "gemini-2.0-flash" : modelName
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
        }
    }

    private func extractResponseText(from data: Data, provider: LLMProvider) throws -> String {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.serverError
        }
        switch provider {
        case .claude:
            guard let content = json["content"] as? [[String: Any]],
                  let text = content.first?["text"] as? String else { throw LLMError.serverError }
            return text
        case .openai:
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String else { throw LLMError.serverError }
            return text
        case .gemini:
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else { throw LLMError.serverError }
            return text
        }
    }

    // MARK: - Private

    private func applyAuthHeaders(to request: inout URLRequest, provider: LLMProvider, apiKey: String) {
        switch provider {
        case .claude:
            request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
            request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        case .openai:
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        case .gemini:
            let url = request.url!
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
            var queryItems = components?.queryItems ?? []
            queryItems.append(URLQueryItem(name: "key", value: apiKey))
            components?.queryItems = queryItems
            request.url = components?.url
        }
    }

    private func buildClaudeBody(messages: [LLMMessage], system: String, modelName: String, stream: Bool = true) throws -> Data {
        let model = modelName.isEmpty ? LLMProvider.claude.defaultModel : modelName
        let encodedMessages = messages.map { msg -> ClaudeMessagePayload in
            if let imgData = msg.imageData {
                return ClaudeMessagePayload(
                    role: msg.role,
                    content: .multipart([
                        .image(ClaudeImageSource(type: "base64", mediaType: "image/jpeg", data: imgData.base64EncodedString())),
                        .text(msg.content)
                    ])
                )
            }
            return ClaudeMessagePayload(role: msg.role, content: .text(msg.content))
        }
        let payload = ClaudeRequestPayload(
            model: model,
            maxTokens: 1024,
            stream: stream,
            system: system.isEmpty ? nil : system,
            messages: encodedMessages
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = .withoutEscapingSlashes
        return try encoder.encode(payload)
    }

    private func buildOpenAIBody(messages: [LLMMessage], system: String, modelName: String, stream: Bool = true) throws -> Data {
        var apiMessages: [[String: Any]] = []
        if !system.isEmpty {
            apiMessages.append(["role": "system", "content": system])
        }
        for msg in messages {
            if let imgData = msg.imageData {
                apiMessages.append([
                    "role": msg.role,
                    "content": [
                        ["type": "text", "text": msg.content],
                        ["type": "image_url", "image_url": ["url": "data:image/jpeg;base64,\(imgData.base64EncodedString())"]]
                    ]
                ])
            } else {
                apiMessages.append(["role": msg.role, "content": msg.content])
            }
        }
        let body: [String: Any] = [
            "model": modelName.isEmpty ? LLMProvider.openai.defaultModel : modelName,
            "stream": stream,
            "messages": apiMessages
        ]
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func buildGeminiBody(messages: [LLMMessage], system: String) throws -> Data {
        let contents: [[String: Any]] = messages.map { msg in
            let role = msg.role == "assistant" ? "model" : "user"
            if let imgData = msg.imageData {
                return [
                    "role": role,
                    "parts": [
                        ["inlineData": ["mimeType": "image/jpeg", "data": imgData.base64EncodedString()]],
                        ["text": msg.content]
                    ]
                ]
            }
            return ["role": role, "parts": [["text": msg.content]]]
        }
        var body: [String: Any] = ["contents": contents]
        if !system.isEmpty {
            body["systemInstruction"] = ["parts": [["text": system]]]
        }
        return try JSONSerialization.data(withJSONObject: body)
    }

    private func parseSSEResponse(data: Data, provider: LLMProvider) -> [String] {
        guard let text = String(data: data, encoding: .utf8) else { return [] }
        let lines = text.components(separatedBy: "\n")
        var chunks: [String] = []

        for line in lines {
            let stripped = line.hasPrefix("data: ") ? String(line.dropFirst(6)) : line
            guard !stripped.isEmpty, stripped != "[DONE]" else { continue }
            guard let lineData = stripped.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            switch provider {
            case .claude:
                if let delta = json["delta"] as? [String: Any],
                   let text = delta["text"] as? String {
                    chunks.append(text)
                }
            case .openai:
                if let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    chunks.append(content)
                }
            case .gemini:
                if let candidates = json["candidates"] as? [[String: Any]],
                   let content = candidates.first?["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let text = parts.first?["text"] as? String {
                    chunks.append(text)
                }
            }
        }
        return chunks
    }
}

// MARK: - Claude Codable Payloads

private struct ClaudeRequestPayload: Encodable {
    let model: String
    let maxTokens: Int
    let stream: Bool
    let system: String?
    let messages: [ClaudeMessagePayload]

    enum CodingKeys: String, CodingKey {
        case model, stream, system, messages
        case maxTokens = "max_tokens"
    }
}

private struct ClaudeImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type, data
        case mediaType = "media_type"
    }
}

private enum ClaudeContentBlock: Encodable {
    case text(String)
    case image(ClaudeImageSource)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .image(let source):
            try container.encode("image", forKey: .type)
            try container.encode(source, forKey: .source)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, text, source
    }
}

private enum ClaudeContent: Encodable {
    case text(String)
    case multipart([ClaudeContentBlock])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .multipart(let blocks):
            try container.encode(blocks)
        }
    }
}

private struct ClaudeMessagePayload: Encodable {
    let role: String
    let content: ClaudeContent
}
