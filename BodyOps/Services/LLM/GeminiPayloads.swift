import Foundation

// Gemini (Generative Language API) のリクエストペイロード

struct GeminiRequestPayload: Encodable {
    let contents: [GeminiContent]
    let systemInstruction: GeminiSystemInstruction?
}

struct GeminiSystemInstruction: Encodable {
    let parts: [GeminiPart]
}

struct GeminiContent: Encodable {
    let role: String
    let parts: [GeminiPart]
}

enum GeminiPart: Encodable {
    case text(String)
    case inlineData(mimeType: String, data: String)

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .text(let value):
            try container.encode(value, forKey: .text)
        case .inlineData(let mimeType, let data):
            try container.encode(GeminiInlineData(mimeType: mimeType, data: data), forKey: .inlineData)
        }
    }

    enum CodingKeys: String, CodingKey {
        case text, inlineData
    }
}

struct GeminiInlineData: Encodable {
    let mimeType: String
    let data: String
}
