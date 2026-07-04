import Foundation

// OpenAI (Chat Completions API) のリクエストペイロード

struct OpenAIRequestPayload: Encodable {
    let model: String
    let stream: Bool
    let streamOptions: OpenAIStreamOptions?
    let messages: [OpenAIMessagePayload]

    enum CodingKeys: String, CodingKey {
        case model, stream, messages
        case streamOptions = "stream_options"
    }
}

struct OpenAIStreamOptions: Encodable {
    let includeUsage: Bool

    enum CodingKeys: String, CodingKey {
        case includeUsage = "include_usage"
    }
}

struct OpenAIMessagePayload: Encodable {
    let role: String
    let content: OpenAIMessageContent
}

enum OpenAIMessageContent: Encodable {
    case text(String)
    case multipart([OpenAIContentPart])

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value):
            try container.encode(value)
        case .multipart(let parts):
            try container.encode(parts)
        }
    }
}

enum OpenAIContentPart: Encodable {
    case text(String)
    case imageURL(String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode("text", forKey: .type)
            try container.encode(value, forKey: .text)
        case .imageURL(let url):
            try container.encode("image_url", forKey: .type)
            try container.encode(OpenAIImageURL(url: url), forKey: .imageURL)
        }
    }

    enum CodingKeys: String, CodingKey {
        case type, text
        case imageURL = "image_url"
    }
}

struct OpenAIImageURL: Encodable {
    let url: String
}
