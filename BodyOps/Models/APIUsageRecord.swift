import Foundation
import SwiftData

@Model
final class APIUsageRecord {
    var recordedAt: Date
    var provider: String
    var modelName: String
    var inputTokens: Int
    var outputTokens: Int
    var costUSD: Double

    init(provider: String, modelName: String, inputTokens: Int, outputTokens: Int) {
        self.recordedAt = Date()
        self.provider = provider
        self.modelName = modelName
        self.inputTokens = inputTokens
        self.outputTokens = outputTokens
        self.costUSD = APIUsageRecord.estimate(
            provider: provider,
            modelName: modelName,
            inputTokens: inputTokens,
            outputTokens: outputTokens
        )
    }

    /// モデル別の概算コスト（USD）を計算する。
    /// 価格は 2025年3月時点の公開料金。実際の請求はプロバイダーのダッシュボードで確認すること。
    static func estimate(provider: String, modelName: String, inputTokens: Int, outputTokens: Int) -> Double {
        let m = modelName.lowercased()
        let inputPer1M: Double
        let outputPer1M: Double

        switch provider {
        case "claude":
            if m.contains("opus") {
                (inputPer1M, outputPer1M) = (15.0, 75.0)
            } else if m.contains("haiku") {
                (inputPer1M, outputPer1M) = (0.80, 4.0)
            } else {
                (inputPer1M, outputPer1M) = (3.0, 15.0) // sonnet
            }
        case "openai":
            if m.contains("mini") {
                (inputPer1M, outputPer1M) = (0.15, 0.60)
            } else if m.contains("turbo") && m.contains("gpt-4") {
                (inputPer1M, outputPer1M) = (10.0, 30.0)
            } else if m.contains("3.5") {
                (inputPer1M, outputPer1M) = (0.50, 1.50)
            } else {
                (inputPer1M, outputPer1M) = (2.50, 10.0) // gpt-4o
            }
        case "gemini":
            if m.contains("flash") {
                (inputPer1M, outputPer1M) = (0.075, 0.30)
            } else {
                (inputPer1M, outputPer1M) = (1.25, 5.0) // 1.5-pro
            }
        default:
            (inputPer1M, outputPer1M) = (0, 0)
        }

        return (Double(inputTokens) / 1_000_000 * inputPer1M)
             + (Double(outputTokens) / 1_000_000 * outputPer1M)
    }
}
