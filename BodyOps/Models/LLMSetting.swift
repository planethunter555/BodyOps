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
        case .claude: return "claude-sonnet-5"
        case .openai: return "gpt-5-mini"
        case .gemini: return "gemini-2.5-flash"
        }
    }

    var models: [String] {
        switch self {
        case .claude:
            // 現行世代はエイリアスID（日付サフィックスなし）を使用する
            return [
                "claude-sonnet-5",
                "claude-sonnet-4-6",
                "claude-sonnet-4-5",
                "claude-haiku-4-5",
                "claude-opus-4-8",
                "claude-opus-4-6"
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

    /// 保存済みの古いClaudeモデルIDを現行モデルへ移行する。
    /// 移行不要な場合は nil を返す。
    static func migratedClaudeModel(for storedName: String) -> String? {
        // まだ有効な日付付きIDはエイリアスIDに置き換えるだけ（モデル自体は変えない）
        let aliasMap: [String: String] = [
            "claude-sonnet-4-5-20250929": "claude-sonnet-4-5",
            "claude-haiku-4-5-20251001": "claude-haiku-4-5"
        ]
        if let alias = aliasMap[storedName] { return alias }

        // 廃止済み・廃止予定のIDは最寄りの現行モデルへ
        let retired: Set<String> = [
            "claude-3-5-sonnet-20241022",
            "claude-3-5-haiku-20241022",
            "claude-3-7-sonnet-20250219",
            "claude-3-opus-20240229",
            "claude-opus-4-20250514",
            "claude-opus-4-1-20250805",
            "claude-sonnet-4-20250514"
        ]
        guard retired.contains(storedName) || storedName.hasPrefix("claude-3") else { return nil }
        if storedName.contains("haiku") { return "claude-haiku-4-5" }
        if storedName.contains("opus") { return "claude-opus-4-8" }
        return "claude-sonnet-5"
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
