import Foundation
import SwiftData

enum LLMProvider: String, CaseIterable, Codable {
    case claude
    case openai
    case gemini

    var displayName: String {
        switch self {
        case .claude: return "Claude (Anthropic)"
        case .openai: return "ChatGPT (OpenAI)"
        case .gemini: return "Gemini (Google)"
        }
    }

    var defaultModel: String {
        switch self {
        case .claude: return "claude-sonnet-4-5-20250929"
        case .openai: return "gpt-5-mini"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    var models: [String] {
        switch self {
        case .claude:
            return [
                "claude-sonnet-4-5-20250929",
                "claude-haiku-4-5-20251001",
                "claude-opus-4-1-20250805",
                "claude-opus-4-20250514",
                "claude-sonnet-4-20250514",
                "claude-3-7-sonnet-20250219",
                "claude-3-5-sonnet-20241022",
                "claude-3-5-haiku-20241022"
            ]
        case .openai:
            return [
                "gpt-5.2-chat-latest",
                "gpt-5.1-chat-latest",
                "gpt-5-chat-latest",
                "gpt-5",
                "gpt-5-mini",
                "gpt-4.1",
                "gpt-4.1-mini",
                "gpt-4o",
                "gpt-4o-mini"
            ]
        case .gemini:
            return [
                "gemini-2.5-flash",
                "gemini-2.5-flash-lite",
                "gemini-2.5-pro",
                "gemini-2.0-flash",
                "gemini-2.0-flash-lite"
            ]
        }
    }
}

@Model
final class LLMSetting {
    var id: UUID
    var providerRaw: String
    var modelName: String
    var apiKey: String
    var updatedAt: Date

    var provider: LLMProvider {
        get { LLMProvider(rawValue: providerRaw) ?? .claude }
        set { providerRaw = newValue.rawValue }
    }

    init(provider: LLMProvider = .claude, modelName: String = "") {
        self.id = UUID()
        self.providerRaw = provider.rawValue
        self.modelName = modelName.isEmpty ? provider.defaultModel : modelName
        self.apiKey = provider.rawValue
        self.updatedAt = Date()
    }
}
