import Foundation

// MARK: - Protocol

protocol URLSessionProtocol {
    func data(for request: URLRequest) async throws -> (Data, URLResponse)
}

extension URLSession: URLSessionProtocol {}

/// SSEレスポンスを行単位で逐次受信する抽象。
/// URLSession.bytes(for:) は具象型のためテストで差し替えられるようにする。
protocol SSELineStreaming: Sendable {
    func lines(for request: URLRequest) async throws -> (lines: AsyncThrowingStream<String, Error>, response: HTTPURLResponse)
}

struct URLSessionSSEStreamer: SSELineStreaming {
    func lines(for request: URLRequest) async throws -> (lines: AsyncThrowingStream<String, Error>, response: HTTPURLResponse) {
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.serverError
        }
        let stream = AsyncThrowingStream<String, Error> { continuation in
            let task = Task {
                do {
                    for try await line in bytes.lines {
                        continuation.yield(line)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        return (stream, httpResponse)
    }
}

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

/// 真のストリーミングで受信するイベント
enum LLMStreamEvent: Equatable, Sendable {
    /// 回答テキストの増分
    case text(String)
    /// 思考（Claude adaptive thinking のサマリー）の増分
    case thinking(String)
    /// トークン使用量（ストリーム完了時に1回）
    case usage(input: Int, output: Int)
}

// MARK: - Service

final class LLMAPIService: @unchecked Sendable {
    private let session: URLSessionProtocol
    private let sseStreamer: SSELineStreaming

    init(session: URLSessionProtocol = URLSession.shared,
         sseStreamer: SSELineStreaming = URLSessionSSEStreamer()) {
        self.session = session
        self.sseStreamer = sseStreamer
    }

    func endpointURL(for provider: LLMProvider, modelName: String = "") -> URL {
        switch provider {
        case .claude:
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://api.anthropic.com/v1/messages")!
        case .openai:
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://api.openai.com/v1/chat/completions")!
        case .gemini:
            let model = modelName.isEmpty ? LLMProvider.gemini.defaultModel : modelName
            // swiftlint:disable:next force_unwrapping
            return URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):streamGenerateContent?alt=sse")!
        }
    }

    func sendMessage(
        messages: [LLMMessage],
        system: String,
        provider: LLMProvider,
        apiKey: String,
        modelName: String = "",
        onUsage: (@Sendable (Int, Int) -> Void)? = nil  // (inputTokens, outputTokens)
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task { @Sendable in
                do {
                    var request = URLRequest(url: endpointURL(for: provider, modelName: modelName))
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
                        let (chunks, inputTokens, outputTokens) = parseSSEResponse(data: data, provider: provider)
                        for chunk in chunks {
                            continuation.yield(chunk)
                        }
                        if inputTokens > 0 || outputTokens > 0 {
                            onUsage?(inputTokens, outputTokens)
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

    /// 真のストリーミング送信。SSEを行単位で受信し、テキスト/思考/使用量イベントを逐次yieldする。
    /// タスクのキャンセルで接続も切断される。
    func streamMessage(
        messages: [LLMMessage],
        system: String,
        provider: LLMProvider,
        apiKey: String,
        modelName: String = ""
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task { @Sendable [sseStreamer] in
                do {
                    var request = URLRequest(url: self.endpointURL(for: provider, modelName: modelName))
                    request.httpMethod = "POST"
                    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                    self.applyAuthHeaders(to: &request, provider: provider, apiKey: apiKey)
                    request.httpBody = try self.buildRequestBody(
                        messages: messages, system: system, provider: provider, modelName: modelName, stream: true
                    )

                    let (lines, httpResponse) = try await sseStreamer.lines(for: request)
                    switch httpResponse.statusCode {
                    case 200: break
                    case 401: throw LLMError.unauthorized
                    case 429: throw LLMError.rateLimited
                    default: throw LLMError.serverError
                    }

                    var inputTokens = 0
                    var outputTokens = 0
                    for try await line in lines {
                        for event in Self.parseSSELine(line, provider: provider) {
                            if case .usage(let input, let output) = event {
                                if input > 0 { inputTokens = input }
                                if output > 0 { outputTokens = output }
                            } else {
                                continuation.yield(event)
                            }
                        }
                    }
                    if inputTokens > 0 || outputTokens > 0 {
                        continuation.yield(.usage(input: inputTokens, output: outputTokens))
                    }
                    continuation.finish()
                } catch let error as LLMError {
                    continuation.finish(throwing: error)
                } catch is CancellationError {
                    // 停止ボタンによるキャンセル: 部分テキストを活かすためエラーにしない
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: LLMError.networkError)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// SSEの1行をプロバイダー別にパースしてイベント列を返す。
    /// usageイベントは途中経過も返す（呼び出し側で最後の値を採用する）。
    static func parseSSELine(_ line: String, provider: LLMProvider) -> [LLMStreamEvent] {
        let stripped = line.hasPrefix("data: ") ? String(line.dropFirst(6)) : line
        guard !stripped.isEmpty, stripped != "[DONE]" else { return [] }
        guard let lineData = stripped.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { return [] }

        var events: [LLMStreamEvent] = []
        switch provider {
        case .claude:
            if let delta = json["delta"] as? [String: Any] {
                if let text = delta["text"] as? String {
                    events.append(.text(text))
                }
                if let thinking = delta["thinking"] as? String {
                    events.append(.thinking(thinking))
                }
            }
            // message_start → input tokens
            if let message = json["message"] as? [String: Any],
               let usage = message["usage"] as? [String: Any],
               let count = usage["input_tokens"] as? Int {
                events.append(.usage(input: count, output: 0))
            }
            // message_delta → output tokens
            if let usage = json["usage"] as? [String: Any],
               let count = usage["output_tokens"] as? Int {
                events.append(.usage(input: 0, output: count))
            }
        case .openai:
            if let choices = json["choices"] as? [[String: Any]],
               let delta = choices.first?["delta"] as? [String: Any],
               let content = delta["content"] as? String {
                events.append(.text(content))
            }
            // stream_options: include_usage: true の最終チャンク
            if let usage = json["usage"] as? [String: Any] {
                events.append(.usage(
                    input: usage["prompt_tokens"] as? Int ?? 0,
                    output: usage["completion_tokens"] as? Int ?? 0
                ))
            }
        case .gemini:
            if let candidates = json["candidates"] as? [[String: Any]],
               let content = candidates.first?["content"] as? [String: Any],
               let parts = content["parts"] as? [[String: Any]],
               let text = parts.first?["text"] as? String {
                events.append(.text(text))
            }
            // usageMetadata は累積値（最後のものが最終値）
            if let meta = json["usageMetadata"] as? [String: Any] {
                events.append(.usage(
                    input: meta["promptTokenCount"] as? Int ?? 0,
                    output: meta["candidatesTokenCount"] as? Int ?? 0
                ))
            }
        }
        return events
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
    /// 戻り値: (レスポンステキスト, inputTokens, outputTokens)
    func sendOnce(
        messages: [LLMMessage],
        system: String,
        provider: LLMProvider,
        apiKey: String,
        modelName: String = ""
    ) async throws -> (text: String, inputTokens: Int, outputTokens: Int) {
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
        case 200: return try extractResponse(from: data, provider: provider)
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

    /// 非ストリーミングレスポンスからテキストとトークン数を抽出する
    private func extractResponse(from data: Data, provider: LLMProvider) throws -> (text: String, inputTokens: Int, outputTokens: Int) {
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw LLMError.serverError
        }
        switch provider {
        case .claude:
            // thinkingブロックが先頭に来る場合があるため、type == "text" のブロックを探す
            guard let content = json["content"] as? [[String: Any]],
                  let text = content.first(where: { $0["type"] as? String == "text" })?["text"] as? String
            else { throw LLMError.serverError }
            let usage = json["usage"] as? [String: Any]
            return (text,
                    usage?["input_tokens"] as? Int ?? 0,
                    usage?["output_tokens"] as? Int ?? 0)
        case .openai:
            guard let choices = json["choices"] as? [[String: Any]],
                  let message = choices.first?["message"] as? [String: Any],
                  let text = message["content"] as? String else { throw LLMError.serverError }
            let usage = json["usage"] as? [String: Any]
            return (text,
                    usage?["prompt_tokens"] as? Int ?? 0,
                    usage?["completion_tokens"] as? Int ?? 0)
        case .gemini:
            guard let candidates = json["candidates"] as? [[String: Any]],
                  let content = candidates.first?["content"] as? [String: Any],
                  let parts = content["parts"] as? [[String: Any]],
                  let text = parts.first?["text"] as? String else { throw LLMError.serverError }
            let meta = json["usageMetadata"] as? [String: Any]
            return (text,
                    meta?["promptTokenCount"] as? Int ?? 0,
                    meta?["candidatesTokenCount"] as? Int ?? 0)
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

    /// adaptive thinking（budget_tokens不要の新方式）に対応しているClaudeモデルか
    static func supportsAdaptiveThinking(_ model: String) -> Bool {
        let prefixes = ["claude-sonnet-4-6", "claude-sonnet-5", "claude-opus-4-6",
                        "claude-opus-4-7", "claude-opus-4-8", "claude-fable"]
        return prefixes.contains { model.hasPrefix($0) }
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
        // ストリーミング（チャット）時のみ思考サマリーを要求する。
        // sendOnce（PFC推定など）は思考ブロックが混ざるとJSONパースの妨げになるため付けない。
        let thinking: ClaudeThinkingConfig? = (stream && Self.supportsAdaptiveThinking(model))
            ? ClaudeThinkingConfig(type: "adaptive", display: "summarized")
            : nil
        let payload = ClaudeRequestPayload(
            model: model,
            maxTokens: thinking != nil ? 4096 : 1024,
            stream: stream,
            system: system.isEmpty ? nil : system,
            thinking: thinking,
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
        var body: [String: Any] = [
            "model": modelName.isEmpty ? LLMProvider.openai.defaultModel : modelName,
            "stream": stream,
            "messages": apiMessages
        ]
        // ストリーミング時はトークン数をレスポンスに含める
        if stream {
            body["stream_options"] = ["include_usage": true]
        }
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

    private func parseSSEResponse(data: Data, provider: LLMProvider) -> (chunks: [String], inputTokens: Int, outputTokens: Int) {
        guard let text = String(data: data, encoding: .utf8) else { return ([], 0, 0) }
        let lines = text.components(separatedBy: "\n")
        var chunks: [String] = []
        var inputTokens = 0
        var outputTokens = 0

        for line in lines {
            let stripped = line.hasPrefix("data: ") ? String(line.dropFirst(6)) : line
            guard !stripped.isEmpty, stripped != "[DONE]" else { continue }
            guard let lineData = stripped.data(using: .utf8),
                  let json = try? JSONSerialization.jsonObject(with: lineData) as? [String: Any] else { continue }

            switch provider {
            case .claude:
                // テキストチャンク
                if let delta = json["delta"] as? [String: Any],
                   let t = delta["text"] as? String {
                    chunks.append(t)
                }
                // message_start → input tokens
                if let message = json["message"] as? [String: Any],
                   let usage = message["usage"] as? [String: Any],
                   let n = usage["input_tokens"] as? Int {
                    inputTokens = n
                }
                // message_delta → output tokens
                if let usage = json["usage"] as? [String: Any],
                   let n = usage["output_tokens"] as? Int {
                    outputTokens = n
                }
            case .openai:
                if let choices = json["choices"] as? [[String: Any]],
                   let delta = choices.first?["delta"] as? [String: Any],
                   let content = delta["content"] as? String {
                    chunks.append(content)
                }
                // stream_options: include_usage: true の最終チャンク
                if let usage = json["usage"] as? [String: Any] {
                    inputTokens = usage["prompt_tokens"] as? Int ?? inputTokens
                    outputTokens = usage["completion_tokens"] as? Int ?? outputTokens
                }
            case .gemini:
                if let candidates = json["candidates"] as? [[String: Any]],
                   let content = candidates.first?["content"] as? [String: Any],
                   let parts = content["parts"] as? [[String: Any]],
                   let t = parts.first?["text"] as? String {
                    chunks.append(t)
                }
                // usageMetadata は累積値なので最後のものを使用
                if let meta = json["usageMetadata"] as? [String: Any] {
                    inputTokens = meta["promptTokenCount"] as? Int ?? inputTokens
                    outputTokens = meta["candidatesTokenCount"] as? Int ?? outputTokens
                }
            }
        }
        return (chunks, inputTokens, outputTokens)
    }
}

// MARK: - Claude Codable Payloads

private struct ClaudeRequestPayload: Encodable {
    let model: String
    let maxTokens: Int
    let stream: Bool
    let system: String?
    let thinking: ClaudeThinkingConfig?
    let messages: [ClaudeMessagePayload]

    enum CodingKeys: String, CodingKey {
        case model, stream, system, thinking, messages
        case maxTokens = "max_tokens"
    }
}

private struct ClaudeThinkingConfig: Encodable {
    let type: String
    let display: String
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
