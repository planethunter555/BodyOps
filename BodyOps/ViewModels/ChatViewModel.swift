import Foundation
import SwiftData
import SwiftUI

/// ストリーミング中の進行状態（インジケータ表示用）
enum ChatStreamPhase {
    case idle
    case connecting
    case thinking
    case streaming
}

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
    var hasConfiguredAPIKey = false
    var streamPhase: ChatStreamPhase = .idle

    // MARK: - Private
    private var context: ModelContext?
    private var streamTask: Task<Void, Never>?
    private var hasPruned = false
    private static let sessionTagKey = "currentChatSessionTag"

    // MARK: - Setup

    func setup(context: ModelContext) {
        self.context = context
        restoreSessionTag()
        refreshConfigurationState()
        loadCurrentSessionMessages()
        // 起動ごとに1回だけ保持ポリシーを適用（古いセッション/画像データの削除）
        if !hasPruned {
            hasPruned = true
            ChatHistoryStore.prune(in: context, keepingCurrent: currentSessionTag)
        }
    }

    /// 前回のセッションタグを復元する（再起動しても会話が消えないように）
    private func restoreSessionTag() {
        if let stored = UserDefaults.standard.string(forKey: Self.sessionTagKey), !stored.isEmpty {
            currentSessionTag = stored
        } else {
            UserDefaults.standard.set(currentSessionTag, forKey: Self.sessionTagKey)
        }
    }

    private func persistSessionTag() {
        UserDefaults.standard.set(currentSessionTag, forKey: Self.sessionTagKey)
    }

    func refreshConfigurationState() {
        hasConfiguredAPIKey = AIClient(setting: fetchLLMSetting()).isConfigured
    }

    /// 現在のプロバイダーが画像入力に対応しているか
    var supportsImageInput: Bool {
        AIClient(setting: fetchLLMSetting()).supportsVision
    }

    /// 現在のプロバイダーがオンデバイス（データを端末外へ送信しない）か
    var isOnDeviceProvider: Bool {
        fetchLLMSetting().provider == .appleOnDevice
    }

    /// 未設定時にバナーへ表示する案内文
    var configurationHint: String {
        AIClient(setting: fetchLLMSetting()).configurationHint
    }

    // MARK: - Send Message

    /// 送信を開始する（停止できるようタスクを保持する）
    func send() {
        streamTask = Task { await sendMessage() }
    }

    /// ストリーミングを停止する。受信済みの部分テキストは保持される。
    func stopStreaming() {
        streamTask?.cancel()
    }

    func sendMessage() async {
        let text = inputText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty || pendingImageData != nil else { return }
        guard let context else { return }

        // 送信可能か確認（クラウド: APIキー / オンデバイス: モデル利用可否）
        let setting = fetchLLMSetting()
        let client = AIClient(setting: setting)
        let apiKey = KeychainService.shared.load(forProvider: setting.provider) ?? ""
        guard client.isConfigured else {
            hasConfiguredAPIKey = false
            errorMessage = client.configurationHint
            return
        }
        hasConfiguredAPIKey = true

        let imageData = pendingImageData
        inputText = ""
        pendingImageData = nil
        errorMessage = nil

        // 履歴は今回のメッセージを保存する前に取得する（重複送信を防ぐ）
        // オンデバイスはコンテキストが小さいためプロンプトをコンパクト化し履歴を絞る
        let systemPrompt = SystemPromptBuilder(context: context).build(compact: client.isOnDevice)
        let apiMessages = buildAPIMessages(
            currentText: text,
            imageData: client.supportsVision ? imageData : nil,
            historyLimit: client.isOnDevice ? 4 : 8,
            context: context
        )

        // ユーザーメッセージをUI＆DBに追加
        let userBubble = ChatBubbleItem(role: "user", content: text, imageData: imageData)
        messages.append(userBubble)
        saveMessage(role: "user", content: text, imageData: imageData, context: context)

        // アシスタントのプレースホルダー
        let assistantBubble = ChatBubbleItem(role: "assistant", content: "")
        messages.append(assistantBubble)
        let assistantIndex = messages.count - 1

        isLoading = true
        streamPhase = .connecting
        defer {
            isLoading = false
            streamPhase = .idle
        }
        let providerRaw = setting.provider.rawValue
        let modelNameCopy = setting.modelName

        var receivedText = ""
        var receivedThinking = ""
        var usageInput = 0
        var usageOutput = 0

        do {
            let stream = client.stream(
                messages: apiMessages,
                system: systemPrompt,
                apiKey: apiKey
            )
            for try await event in stream {
                switch event {
                case .thinking(let delta):
                    receivedThinking += delta
                    messages[assistantIndex].thinking = receivedThinking
                    if streamPhase == .connecting { streamPhase = .thinking }
                case .text(let delta):
                    receivedText += delta
                    messages[assistantIndex].content = receivedText
                    streamPhase = .streaming
                case .usage(let input, let output):
                    usageInput = input
                    usageOutput = output
                }
            }

            if usageInput > 0 || usageOutput > 0 {
                let record = APIUsageRecord(
                    provider: providerRaw,
                    modelName: modelNameCopy,
                    inputTokens: usageInput,
                    outputTokens: usageOutput
                )
                context.insert(record)
                try? context.save()
            }

            let responseText = receivedText.trimmingCharacters(in: .whitespacesAndNewlines)
            if responseText.isEmpty {
                messages[assistantIndex].content = "応答が空でした。モデルを変更するか、時間をおいて再試行してください。"
            } else {
                messages[assistantIndex].content = responseText
            }
            saveMessage(role: "assistant", content: messages[assistantIndex].content, imageData: nil, context: context)
        } catch let error as LLMError {
            // 途中まで受信できていれば部分テキストを保持してエラー行を追記する
            if receivedText.isEmpty {
                messages[assistantIndex].content = errorText(for: error)
            } else {
                messages[assistantIndex].content = receivedText + "\n\n⚠️ " + errorText(for: error)
                saveMessage(role: "assistant", content: receivedText, imageData: nil, context: context)
            }
            errorMessage = errorText(for: error)
        } catch {
            messages[assistantIndex].content = "エラーが発生しました。再試行してください。"
        }
    }

    // MARK: - New Chat

    func startNewChat() {
        currentSessionTag = UUID().uuidString
        persistSessionTag()
        messages = []
        errorMessage = nil
    }

    // MARK: - Session History

    /// 過去のセッションを読み込んで表示する（続きから送信も可能）
    func loadSession(tag: String) {
        guard let context else { return }
        stopStreaming()
        currentSessionTag = tag
        persistSessionTag()
        errorMessage = nil
        let stored = ChatHistoryStore.messages(tag: tag, in: context)
        messages = stored.map { ChatBubbleItem(role: $0.role, content: $0.content, imageData: $0.imageData) }
    }

    /// セッション一覧（履歴シート用）
    func sessionSummaries() -> [ChatSessionSummary] {
        guard let context else { return [] }
        return ChatHistoryStore.sessions(in: context)
    }

    /// セッションを削除する。現在表示中のセッションを消した場合は新規会話に切り替える。
    func deleteSession(tag: String) {
        guard let context else { return }
        ChatHistoryStore.deleteSession(tag: tag, in: context)
        if tag == currentSessionTag {
            startNewChat()
        }
    }

    // MARK: - Context Building

    /// デバッグ用: 現在のシステムプロンプトを返す
    func previewSystemPrompt() -> String {
        guard let context else { return "（コンテキスト未設定）" }
        return SystemPromptBuilder(context: context).build()
    }

    private func buildAPIMessages(currentText: String, imageData: Data?, historyLimit: Int = 8, context: ModelContext) -> [LLMMessage] {
        var result: [LLMMessage] = []

        // 現在のセッションの直近履歴（画像は除外してテキストのみ送信 - メモリ節約）
        let history = fetchSessionHistory(limit: historyLimit, context: context)
        for msg in history {
            result.append(LLMMessage(role: msg.role, content: msg.content, imageData: nil))
        }

        // 今回のユーザーメッセージ
        result.append(LLMMessage(role: "user", content: currentText, imageData: imageData))

        return Self.normalizedForAPI(result)
    }

    /// LLM APIの要求形式に合わせて履歴を正規化する。
    /// - 空メッセージを除外（送信失敗時などに空のまま残ったもの）
    /// - 先頭はuserでなければならない
    /// - 同じroleの連続はマージ（送信失敗でAIの返信が無いままuserが続くと400になるプロバイダーがある）
    static func normalizedForAPI(_ messages: [LLMMessage]) -> [LLMMessage] {
        var result: [LLMMessage] = []
        for msg in messages {
            let isEmpty = msg.content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            guard !isEmpty || msg.imageData != nil else { continue }
            if result.isEmpty && msg.role != "user" { continue }
            if let last = result.last, last.role == msg.role {
                result[result.count - 1] = LLMMessage(
                    role: msg.role,
                    content: last.content.isEmpty ? msg.content : last.content + "\n\n" + msg.content,
                    imageData: msg.imageData ?? last.imageData
                )
            } else {
                result.append(msg)
            }
        }
        return result
    }

    // MARK: - Data Fetching

    private func fetchLLMSetting() -> LLMSetting {
        guard let context else { return LLMSetting() }
        return (try? LLMSettingsStore.current(in: context)) ?? LLMSetting()
    }

    /// LLMに渡す会話コンテキスト。現在のセッション内の直近N件に限定する
    /// （セッションをまたぐと文脈が混ざるため、セッション内スコープとする）
    private func fetchSessionHistory(limit: Int, context: ModelContext) -> [ChatMessage] {
        let tag = currentSessionTag
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.sessionTag == tag },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        let all = (try? context.fetch(descriptor)) ?? []
        return Array(all.suffix(limit))
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
        case .badRequest(let status):
            return "リクエストエラー(コード\(status))が発生しました。解決しない場合は「新しい会話」を開始するか、設定でモデルを変更してみてください。"
        case .serverError: return "サーバーエラーが発生しました。再試行してください。"
        case .networkError: return "ネットワークエラーです。接続を確認してください。"
        case .contextTooLong: return "会話が長くなりすぎました。「新しい会話」を開始してください。"
        }
    }

    var hasAPIKey: Bool {
        hasConfiguredAPIKey
    }

    var currentModelDescription: String {
        let setting = fetchLLMSetting()
        let model = setting.modelName.isEmpty ? "ー" : setting.modelName
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
    /// Claudeのadaptive thinking（要約された思考）テキスト
    var thinking: String?

    var isUser: Bool { role == "user" }
}
