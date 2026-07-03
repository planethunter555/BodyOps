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

    var canSave: Bool {
        let hasNutrition = calories > 0 || protein > 0 || fat > 0 || carbs > 0
        let hasDescription = !mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasNutrition || hasDescription || imageData != nil
    }

    func estimatePFC(context: ModelContext) async {
        let trimmed = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageData != nil else { return }

        let setting = fetchLLMSetting(context: context)
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

    func currentProviderDescription(context: ModelContext) -> String {
        fetchLLMSetting(context: context).provider.displayName
    }

    func load(from meal: MealRecord) {
        mealDescription = meal.mealDescription
        mealType = meal.mealType
        imageData = meal.imageData
        calories = meal.calories
        protein = meal.protein
        fat = meal.fat
        carbs = meal.carbs
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
}
