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
        case .claude: return "claude-sonnet-4-6"
        case .openai: return "gpt-4o"
        case .gemini: return "gemini-2.0-flash"
        }
    }

    var models: [String] {
        switch self {
        case .claude: return ["claude-sonnet-4-6", "claude-opus-4-6", "claude-haiku-4-5-20251001"]
        case .openai: return ["gpt-4o", "gpt-4o-mini", "gpt-4-turbo", "gpt-3.5-turbo"]
        case .gemini: return ["gemini-2.0-flash", "gemini-1.5-pro", "gemini-1.5-flash"]
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
