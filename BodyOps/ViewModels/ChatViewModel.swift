import Foundation
import SwiftData
import SwiftUI

@Observable
@MainActor
final class ChatViewModel {
    // MARK: - Published State
    var messages: [ChatBubbleItem] = []
    var inputText: String = ""
    var isLoading = false
    var errorMessage: String?
    var pendingImageData: Data?
    var currentSessionTag: String = UUID().uuidString

    // MARK: - Private
    private var context: ModelContext?
    private let llmService = LLMAPIService()

    // MARK: - Setup

    func setup(context: ModelContext) {
        self.context = context
        loadCurrentSessionMessages()
    }

    // MARK: - Send Message

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImageData != nil else { return }
        guard let context else { return }

        // APIキー確認
        let setting = fetchLLMSetting()
        let apiKey = KeychainService.shared.load(forProvider: setting.provider) ?? ""
        guard !apiKey.isEmpty else {
            errorMessage = "APIキーが設定されていません。設定タブで入力してください。"
            return
        }

        let imageData = pendingImageData
        inputText = ""
        pendingImageData = nil
        errorMessage = nil

        // ユーザーメッセージをUI＆DBに追加
        let userBubble = ChatBubbleItem(role: "user", content: text, imageData: imageData)
        messages.append(userBubble)
        saveMessage(role: "user", content: text, imageData: imageData, context: context)

        // アシスタントのプレースホルダー
        let assistantBubble = ChatBubbleItem(role: "assistant", content: "")
        messages.append(assistantBubble)
        let assistantIndex = messages.count - 1

        isLoading = true
        defer { isLoading = false }

        do {
            let systemPrompt = buildSystemPrompt(context: context)
            let apiMessages = buildAPIMessages(currentText: text, imageData: imageData, context: context)

            let providerRaw = setting.provider.rawValue
            let modelNameCopy = setting.modelName
            let response = try await llmService.sendOnce(
                messages: apiMessages,
                system: systemPrompt,
                provider: setting.provider,
                apiKey: apiKey,
                modelName: setting.modelName
            )

            let record = APIUsageRecord(
                provider: providerRaw,
                modelName: modelNameCopy,
                inputTokens: response.inputTokens,
                outputTokens: response.outputTokens
            )
            context.insert(record)
            try? context.save()

            let responseText = response.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if responseText.isEmpty {
                messages[assistantIndex].content = "応答が空でした。モデルを変更するか、時間をおいて再試行してください。"
            } else {
                messages[assistantIndex].content = responseText
            }

            saveMessage(role: "assistant", content: messages[assistantIndex].content, imageData: nil, context: context)
        } catch let error as LLMError {
            messages[assistantIndex].content = errorText(for: error)
            errorMessage = errorText(for: error)
        } catch {
            messages[assistantIndex].content = "エラーが発生しました。再試行してください。"
        }
    }

    // MARK: - New Chat

    func startNewChat() {
        currentSessionTag = UUID().uuidString
        messages = []
        errorMessage = nil
    }

    // MARK: - Context Building

    private func buildSystemPrompt(context: ModelContext) -> String {
        SystemPromptBuilder(context: context).build()
    }

    /// デバッグ用: 現在のシステムプロンプトを返す
    func previewSystemPrompt() -> String {
        guard let context else { return "（コンテキスト未設定）" }
        return SystemPromptBuilder(context: context).build()
    }

    private func buildAPIMessages(currentText: String, imageData: Data?, context: ModelContext) -> [LLMMessage] {
        var result: [LLMMessage] = []

        // 過去1週間の会話履歴（画像は除外してテキストのみ送信 - メモリ節約）
        let history = fetchWeeklyHistory(context: context)
        for msg in history {
            result.append(LLMMessage(role: msg.role, content: msg.content, imageData: nil))
        }

        // 今回のユーザーメッセージ
        result.append(LLMMessage(role: "user", content: currentText, imageData: imageData))

        return result
    }

    // MARK: - Data Fetching

    private func fetchLLMSetting() -> LLMSetting {
        guard let context else { return LLMSetting() }
        let descriptor = FetchDescriptor<LLMSetting>()
        return (try? context.fetch(descriptor).first) ?? LLMSetting()
    }

    private func fetchWeeklyHistory(context: ModelContext) -> [ChatMessage] {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.createdAt >= oneWeekAgo },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        // 最新の会話のみ（コンテキスト肥大化防止で最大8件）
        let all = (try? context.fetch(descriptor)) ?? []
        return Array(all.suffix(8))
    }

    // MARK: - Persistence

    private func loadCurrentSessionMessages() {
        guard let context else { return }
        let tag = currentSessionTag
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.sessionTag == tag },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let stored = (try? context.fetch(descriptor)) ?? []
        messages = stored.map { ChatBubbleItem(role: $0.role, content: $0.content, imageData: $0.imageData) }
    }

    private func saveMessage(role: String, content: String, imageData: Data?, context: ModelContext) {
        let msg = ChatMessage(role: role, content: content, chatType: "workout_advice", sessionTag: currentSessionTag)
        msg.imageData = imageData
        context.insert(msg)
        try? context.save()
    }

    // MARK: - Helpers

    private func errorText(for error: LLMError) -> String {
        switch error {
        case .unauthorized: return "APIキーが無効です。設定タブで確認してください。"
        case .rateLimited: return "リクエストが多すぎます。しばらく待ってから再試行してください。"
        case .serverError: return "サーバーエラーが発生しました。再試行してください。"
        case .networkError: return "ネットワークエラーです。接続を確認してください。"
        }
    }

    var hasAPIKey: Bool {
        let setting = fetchLLMSetting()
        return KeychainService.shared.load(forProvider: setting.provider) != nil
    }

    var currentModelDescription: String {
        let setting = fetchLLMSetting()
        let model = setting.modelName.isEmpty ? setting.provider.defaultModel : setting.modelName
        return "\(setting.provider.displayName)  |  \(model)"
    }

    var currentProviderDescription: String {
        fetchLLMSetting().provider.displayName
    }
}

// MARK: - Chat Bubble Model

struct ChatBubbleItem: Identifiable {
    let id = UUID()
    var role: String
    var content: String
    var imageData: Data?

    var isUser: Bool { role == "user" }
}
