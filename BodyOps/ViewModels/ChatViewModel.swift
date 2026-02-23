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
        var assistantBubble = ChatBubbleItem(role: "assistant", content: "")
        messages.append(assistantBubble)
        let assistantIndex = messages.count - 1

        isLoading = true
        defer { isLoading = false }

        do {
            let systemPrompt = buildSystemPrompt(context: context)
            let apiMessages = buildAPIMessages(currentText: text, imageData: imageData, context: context)

            let stream = llmService.sendMessage(
                messages: apiMessages,
                system: systemPrompt,
                provider: setting.provider,
                apiKey: apiKey,
                modelName: setting.modelName
            )

            var fullResponse = ""
            for try await chunk in stream {
                fullResponse += chunk
                messages[assistantIndex].content = fullResponse
            }

            saveMessage(role: "assistant", content: fullResponse, imageData: nil, context: context)
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
        let profile = fetchProfile(context: context)
        let setting = fetchLLMSetting()
        var parts: [String] = []

        // Pre-fix プロンプト（ユーザー設定）
        if !setting.modelName.isEmpty, let prefix = profile?.systemPromptPrefix, !prefix.isEmpty {
            parts.append(prefix)
        } else if let prefix = profile?.systemPromptPrefix, !prefix.isEmpty {
            parts.append(prefix)
        }

        // ベースシステムプロンプト
        parts.append("あなたは「Body Ops」専属のパーソナルトレーナー兼栄養士です。ユーザーの記録に基づき、科学的根拠のある具体的なアドバイスを日本語で提供してください。")

        // プロファイル情報
        if let prof = profile {
            parts.append("""
            ## ユーザープロファイル
            - 身長: \(prof.height)cm / 体重: \(prof.weight)kg / 体脂肪率: \(prof.bodyFatPercentage)%
            - 目標筋肉量: \(prof.targetMuscleMass)kg / 目標体脂肪率: \(prof.targetBodyFat)%
            - 週のトレーニング可能日数: \(prof.weeklyWorkoutDays)日
            """)

            if !prof.goals.isEmpty {
                parts.append("## 目標\n\(prof.goals)")
            }
            if !prof.constraints.isEmpty {
                parts.append("## 制約・要望\n\(prof.constraints)")
            }
        }

        // 直近3セッションの筋トレ記録
        let recentSessions = fetchRecentSessions(context: context, limit: 3)
        if !recentSessions.isEmpty {
            var workoutLines = ["## 直近のトレーニング記録"]
            for session in recentSessions {
                let dateStr = formatDate(session.date)
                let grouped = Dictionary(grouping: session.sets) { $0.exercise?.name ?? "不明" }
                let exerciseLines = grouped.map { name, sets in
                    let setDesc = sets.sorted { $0.setNumber < $1.setNumber }
                        .map { "\($0.weight)kg×\($0.reps)回" }
                        .joined(separator: ", ")
                    return "  - \(name): \(setDesc)"
                }.joined(separator: "\n")
                workoutLines.append("[\(dateStr)]\n\(exerciseLines)")
                if !session.memo.isEmpty {
                    workoutLines.append("  メモ: \(session.memo)")
                }
            }
            parts.append(workoutLines.joined(separator: "\n"))
        }

        // 当日・前日の食事
        let recentMeals = fetchRecentMeals(context: context)
        if !recentMeals.isEmpty {
            var mealLines = ["## 直近の食事記録"]
            for meal in recentMeals {
                let mealEntry = "- \(meal.mealType)（\(formatDate(meal.recordedAt))）: " +
                    "\(Int(meal.calories))kcal, P\(Int(meal.protein))g F\(Int(meal.fat))g C\(Int(meal.carbs))g"
                mealLines.append(mealEntry)
            }
            parts.append(mealLines.joined(separator: "\n"))
        }

        parts.append("## ルール\n- 具体的な数値（重量・セット数・回数・PFC）を含める\n- 制約事項を必ず考慮する\n- 怪我リスクには警告する\n- 回答は日本語で400字以内")

        return parts.joined(separator: "\n\n")
    }

    private func buildAPIMessages(currentText: String, imageData: Data?, context: ModelContext) -> [LLMMessage] {
        var result: [LLMMessage] = []

        // 過去1週間の会話履歴（現在のセッション問わず）
        let history = fetchWeeklyHistory(context: context)
        for msg in history {
            result.append(LLMMessage(role: msg.role, content: msg.content, imageData: msg.imageData))
        }

        // 今回のユーザーメッセージ
        result.append(LLMMessage(role: "user", content: currentText, imageData: imageData))

        return result
    }

    // MARK: - Data Fetching

    private func fetchProfile(context: ModelContext) -> UserProfile? {
        let descriptor = FetchDescriptor<UserProfile>()
        return try? context.fetch(descriptor).first
    }

    private func fetchLLMSetting() -> LLMSetting {
        guard let context else { return LLMSetting() }
        let descriptor = FetchDescriptor<LLMSetting>()
        return (try? context.fetch(descriptor).first) ?? LLMSetting()
    }

    private func fetchRecentSessions(context: ModelContext, limit: Int) -> [WorkoutSession] {
        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchRecentMeals(context: ModelContext) -> [MealRecord] {
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<MealRecord>(
            predicate: #Predicate { $0.recordedAt >= twoDaysAgo },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func fetchWeeklyHistory(context: ModelContext) -> [ChatMessage] {
        let oneWeekAgo = Calendar.current.date(byAdding: .day, value: -7, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.createdAt >= oneWeekAgo },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        // 最新の会話のみ（コンテキスト肥大化防止で最大30件）
        let all = (try? context.fetch(descriptor)) ?? []
        return Array(all.suffix(30))
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

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

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
}

// MARK: - Chat Bubble Model

struct ChatBubbleItem: Identifiable {
    let id = UUID()
    var role: String
    var content: String
    var imageData: Data?

    var isUser: Bool { role == "user" }
}
