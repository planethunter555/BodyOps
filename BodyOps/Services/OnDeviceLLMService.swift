#if canImport(FoundationModels)
import Foundation
import FoundationModels

/// Apple Intelligence（FoundationModels）によるオンデバイス推論サービス。
/// このファイル全体が iOS 26 SDK 以降でのみコンパイルされる。
/// コンテキストウィンドウが小さい（約4Kトークン）ため、呼び出し側で
/// システムプロンプトのコンパクト化と履歴の制限を行うこと。
@available(iOS 26.0, *)
struct OnDeviceLLMService {

    /// 会話履歴を1つのプロンプトに連結する（小さなコンテキスト向けの簡易方式）
    static func buildPrompt(messages: [LLMMessage]) -> String {
        guard messages.count > 1 else { return messages.first?.content ?? "" }
        var lines: [String] = ["これまでの会話:"]
        for msg in messages.dropLast() {
            let speaker = msg.role == "assistant" ? "コーチ" : "ユーザー"
            lines.append("\(speaker): \(msg.content)")
        }
        lines.append("")
        lines.append("ユーザーの新しいメッセージ: \(messages.last?.content ?? "")")
        return lines.joined(separator: "\n")
    }

    /// FoundationModelsのエラーをアプリ共通のLLMErrorへマップする。
    /// 型名に依存しない判定（enumケース名はSDKバージョンで変わりうるため文字列で判定）
    static func mapError(_ error: Error) -> LLMError {
        if String(describing: error).localizedCaseInsensitiveContains("contextwindow") {
            return .contextTooLong
        }
        return .serverError
    }

    /// 単発の応答（接続テスト・フォールバック用）
    func respond(messages: [LLMMessage], system: String) async throws -> String {
        let session = LanguageModelSession(instructions: system)
        do {
            let response = try await session.respond(to: Self.buildPrompt(messages: messages))
            return response.content
        } catch {
            throw Self.mapError(error)
        }
    }

    /// ストリーミング応答。FoundationModelsのスナップショットは累積テキストのため、
    /// 前回との差分をデルタとしてyieldしてクラウドAPIと同じイベント形式に揃える。
    func stream(messages: [LLMMessage], system: String) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let session = LanguageModelSession(instructions: system)
                    var previous = ""
                    for try await snapshot in session.streamResponse(to: Self.buildPrompt(messages: messages)) {
                        let cumulative = snapshot.content
                        if cumulative.count > previous.count {
                            let delta = String(cumulative.dropFirst(previous.count))
                            continuation.yield(.text(delta))
                            previous = cumulative
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: Self.mapError(error))
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// 食事のPFC推定。guided generationで構造化された結果を保証する（JSONパース不要）。
    func estimateMeal(description: String) async throws -> OnDeviceMealEstimate {
        let session = LanguageModelSession(
            instructions: "あなたは栄養士です。食事内容からカロリーとPFC（タンパク質・脂質・炭水化物）を推定してください。"
        )
        let response = try await session.respond(
            to: "以下の食事のカロリーとPFCを推定してください。\n食事内容: \(description)",
            generating: OnDeviceMealEstimate.self
        )
        return response.content
    }
}

@available(iOS 26.0, *)
@Generable
struct OnDeviceMealEstimate {
    @Guide(description: "推定総カロリー（kcal）")
    var calories: Double
    @Guide(description: "タンパク質（g）")
    var protein: Double
    @Guide(description: "脂質（g）")
    var fat: Double
    @Guide(description: "炭水化物（g）")
    var carbs: Double
    @Guide(description: "推定の簡単な説明（1文）")
    var summary: String
}
#endif
