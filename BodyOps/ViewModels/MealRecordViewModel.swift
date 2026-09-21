import SwiftUI
import SwiftData

// MARK: - Models

struct EstimationItem {
    let name: String
    let amount: String
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double
}

struct EstimationDetails {
    let items: [EstimationItem]
    let summary: String?
}

enum MealType: String, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack

    var label: String {
        switch self {
        case .breakfast: return "朝"
        case .lunch: return "昼"
        case .dinner: return "夜"
        case .snack: return "間食"
        }
    }
}

/// AI推定の進行状態（確認画面のステータスバナー表示用）
enum EstimationPhase: Equatable {
    case idle
    case estimating
    case done
    case failed(String)
}

/// 食事記録の入力方式。入力画面のレイアウトがこれによって変わる。
enum MealEntryMode {
    /// 写真からAI推定（写真が主役、推定は自動実行）
    case photo
    /// テキストからAI推定（食事内容の入力と推定ボタンが主役）
    case textAI
    /// 手動入力（AI関連のUIは表示しない）
    case manual
}

// MARK: - ViewModel

@Observable
@MainActor
final class MealRecordViewModel {
    var mealDescription: String = ""
    var mealType: String = MealType.lunch.rawValue
    var imageData: Data?
    var calories: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0
    var isEstimating = false
    var estimationError: String?
    var estimationSucceeded = false
    var estimationDetails: EstimationDetails?

    var previewImage: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    var estimationPhase: EstimationPhase {
        if isEstimating { return .estimating }
        if let error = estimationError { return .failed(error) }
        if estimationSucceeded { return .done }
        return .idle
    }

    var cannotEstimate: Bool {
        let empty = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return isEstimating || (empty && imageData == nil)
    }

    /// 栄養素が1つでも入力されているか
    var hasNutritionInput: Bool {
        calories > 0 || protein > 0 || fat > 0 || carbs > 0
    }

    /// AI推定を一度でも実行したか（成功・失敗を問わない）
    var estimationAttempted: Bool {
        estimationSucceeded || estimationError != nil
    }

    var canSave: Bool {
        let hasDescription = !mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasNutritionInput || hasDescription || imageData != nil
    }

    func estimatePFC(context: ModelContext) async {
        let trimmed = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageData != nil else { return }

        let setting = fetchLLMSetting(context: context)
        let client = AIClient(setting: setting)

        // オンデバイスAIは画像解析非対応・guided generationで推定する
        if client.isOnDevice {
            await estimateOnDevice(description: trimmed)
            return
        }

        let apiKey = KeychainService.shared.load(forProvider: setting.provider) ?? ""
        guard !apiKey.isEmpty else {
            estimationError = "APIキーが設定されていません。設定タブで入力してください。"
            return
        }

        isEstimating = true
        estimationError = nil
        estimationSucceeded = false
        defer { isEstimating = false }

        let messages = [LLMMessage(role: "user", content: buildPrompt(description: trimmed), imageData: imageData)]
        let system = "栄養の専門家として、必ずJSONのみで返答してください。説明やmarkdownは不要です。"

        do {
            // stream: false の非ストリーミングリクエストで1回確実に取得する
            let result = try await LLMAPIService().sendOnce(
                messages: messages,
                system: system,
                provider: setting.provider,
                apiKey: apiKey,
                modelName: setting.modelName
            )
            parseAndApply(response: result.text)
            // API使用量を記録
            let record = APIUsageRecord(
                provider: setting.provider.rawValue,
                modelName: setting.modelName,
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens
            )
            context.insert(record)
            try? context.save()
        } catch {
            estimationError = "AI推定に失敗しました。手動で入力してください。"
        }
    }

    /// Apple Intelligence（オンデバイス）による推定。テキストのみ対応。
    private func estimateOnDevice(description: String) async {
        guard !description.isEmpty else {
            estimationError = "Apple Intelligence（オンデバイス）は画像解析に対応していません。食事内容をテキストで入力してください。写真はメモとして保存されます。"
            return
        }

        #if canImport(FoundationModels)
        if #available(iOS 26.0, *) {
            guard OnDeviceAvailability.check().isAvailable else {
                estimationError = "Apple Intelligenceが利用できません。\(OnDeviceAvailability.check().statusDescription)"
                return
            }
            isEstimating = true
            estimationError = nil
            estimationSucceeded = false
            defer { isEstimating = false }

            do {
                let result = try await OnDeviceLLMService().estimateMeal(description: description)
                calories = result.calories
                protein = result.protein
                fat = result.fat
                carbs = result.carbs
                estimationDetails = EstimationDetails(items: [], summary: result.summary)
                estimationSucceeded = true
            } catch {
                estimationError = "オンデバイスAIが応答できませんでした。クラウドAIをお試しください。"
            }
            return
        }
        #endif
        estimationError = "この端末ではオンデバイスAIを利用できません。設定でクラウドAIを選択してください。"
    }

    func currentProviderDescription(context: ModelContext) -> String {
        fetchLLMSetting(context: context).provider.displayName
    }

    func isOnDeviceProvider(context: ModelContext) -> Bool {
        fetchLLMSetting(context: context).provider == .appleOnDevice
    }

    func load(from meal: MealRecord) {
        mealDescription = meal.mealDescription
        mealType = meal.mealType
        imageData = meal.imageData
        calories = meal.calories
        protein = meal.protein
        fat = meal.fat
        carbs = meal.carbs
        estimationSucceeded = false
        estimationError = nil
        estimationDetails = nil
    }

    /// 入力内容を初期化する（食事タイプは保持）。編集画面から入力方法選択へ戻る際に使う。
    func reset() {
        mealDescription = ""
        imageData = nil
        calories = 0
        protein = 0
        fat = 0
        carbs = 0
        isEstimating = false
        estimationError = nil
        estimationSucceeded = false
        estimationDetails = nil
    }

    func update(meal: MealRecord, context: ModelContext) {
        meal.mealDescription = mealDescription
        meal.mealType = mealType
        meal.imageData = imageData
        meal.calories = calories
        meal.protein = protein
        meal.fat = fat
        meal.carbs = carbs
        try? context.save()
        enqueueMealForIntake(meal, context: context)
    }

    func save(date: Date, context: ModelContext) {
        let record = MealRecord(
            mealDescription: mealDescription,
            mealType: mealType,
            calories: calories,
            protein: protein,
            fat: fat,
            carbs: carbs
        )
        record.imageData = imageData
        record.recordedAt = resolvedDate(for: date)
        context.insert(record)
        try? context.save()
        enqueueMealForIntake(record, context: context)
    }

    // MARK: - Private

    private func fetchLLMSetting(context: ModelContext) -> LLMSetting {
        (try? LLMSettingsStore.current(in: context)) ?? LLMSetting()
    }

    private func buildPrompt(description: String) -> String {
        var parts = ["以下の食事のカロリーとPFCを推定してください。"]
        if !description.isEmpty { parts.append("食事内容: \(description)") }
        if imageData != nil { parts.append("（添付の食事写真も参考にしてください）") }
        parts.append("""
        JSON形式のみで返答してください:
        {
          "total": {
            "calories": 数値,
            "protein": 数値,
            "fat": 数値,
            "carbs": 数値
          },
          "items": [
            {
              "name": "食材名",
              "amount": "分量",
              "calories": 数値,
              "protein": 数値,
              "fat": 数値,
              "carbs": 数値
            }
          ],
          "summary": "簡単な説明（1文）"
        }
        """)
        return parts.joined(separator: "\n")
    }

    private func parseAndApply(response: String) {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            estimationError = "JSONの解析に失敗しました。手動で入力してください。"
            return
        }
        let jsonString = String(cleaned[start...end])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            estimationError = "JSONの解析に失敗しました。手動で入力してください。"
            return
        }

        // 新形式を試す
        if let total = json["total"] as? [String: Any] {
            calories = numericValue(total["calories"])
            protein = numericValue(total["protein"])
            fat = numericValue(total["fat"])
            carbs = numericValue(total["carbs"])

            var items: [EstimationItem] = []
            if let itemsArray = json["items"] as? [[String: Any]] {
                for itemDict in itemsArray {
                    let item = EstimationItem(
                        name: itemDict["name"] as? String ?? "",
                        amount: itemDict["amount"] as? String ?? "",
                        calories: numericValue(itemDict["calories"]),
                        protein: numericValue(itemDict["protein"]),
                        fat: numericValue(itemDict["fat"]),
                        carbs: numericValue(itemDict["carbs"])
                    )
                    items.append(item)
                }
            }

            let summary = json["summary"] as? String
            estimationDetails = EstimationDetails(items: items, summary: summary)
            estimationSucceeded = true
        } else {
            // 旧形式（後方互換性）
            calories = numericValue(json["calories"])
            protein = numericValue(json["protein"])
            fat = numericValue(json["fat"])
            carbs = numericValue(json["carbs"])
            estimationDetails = EstimationDetails(items: [], summary: nil)
            estimationSucceeded = true
        }
    }

    private func numericValue(_ value: Any?) -> Double {
        if let val = value as? Double { return val }
        if let val = value as? Int { return Double(val) }
        return 0
    }

    private func resolvedDate(for date: Date) -> Date {
        Calendar.current.isDateInToday(date) ? Date() : date
    }

    private func enqueueMealForIntake(_ meal: MealRecord, context: ModelContext) {
        do {
            try IntakeSyncService(context: context).enqueue(meal: meal)
            Task { @MainActor in
                await IntakeSyncService(context: context).flushPending()
            }
        } catch {
            // ローカル保存を優先する。同期できない場合は次回の保存/起動時に再送を試す。
        }
    }
}
