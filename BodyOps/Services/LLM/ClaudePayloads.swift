import Foundation

// Claude (Anthropic Messages API) のリクエストペイロード

struct ClaudeRequestPayload: Encodable {
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

struct ClaudeThinkingConfig: Encodable {
    let type: String
    let display: String
}

struct ClaudeImageSource: Encodable {
    let type: String
    let mediaType: String
    let data: String

    enum CodingKeys: String, CodingKey {
        case type, data
        case mediaType = "media_type"
    }
}

enum ClaudeContentBlock: Encodable {
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

enum ClaudeContent: Encodable {
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

struct ClaudeMessagePayload: Encodable {
    let role: String
    let content: ClaudeContent
}
