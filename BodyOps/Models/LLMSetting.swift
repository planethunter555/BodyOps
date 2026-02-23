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
