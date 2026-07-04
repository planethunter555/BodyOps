import Foundation

/// クラウドLLM API（Claude/OpenAI/Gemini）とオンデバイスLLM（Apple Intelligence）を
/// 同一のインターフェースで扱う薄いルーター。
/// ChatViewModel / MealRecordViewModel はこのクライアント経由でAIを呼び出す。
struct AIClient {
    let provider: LLMProvider
    let modelName: String

    init(setting: LLMSetting) {
        self.provider = setting.provider
        self.modelName = setting.modelName
    }

    var isOnDevice: Bool { provider == .appleOnDevice }

    /// 画像入力（vision）に対応しているか。オンデバイスモデルは非対応。
    var supportsVision: Bool { !isOnDevice }

    var requiresAPIKey: Bool { !isOnDevice }

    /// 送信可能な状態か（クラウド: APIキー設定済み / オンデバイス: モデル利用可能）
    var isConfigured: Bool {
        if isOnDevice {
            return OnDeviceAvailability.check().isAvailable
        }
        return !(KeychainService.shared.load(forProvider: provider) ?? "").isEmpty
    }

    /// 未設定時にユーザーへ表示する案内文
    var configurationHint: String {
        if isOnDevice {
            return "Apple Intelligenceが利用できません。\(OnDeviceAvailability.check().statusDescription)"
        }
        return "APIキーが設定されていません。設定タブで入力してください。"
    }

    /// ストリーミング送信（チャット用）
    func stream(
        messages: [LLMMessage],
        system: String,
        apiKey: String
    ) -> AsyncThrowingStream<LLMStreamEvent, Error> {
        if isOnDevice {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                return OnDeviceLLMService().stream(messages: messages, system: system)
            }
            #endif
            return Self.unavailableStream()
        }
        return LLMAPIService().streamMessage(
            messages: messages,
            system: system,
            provider: provider,
            apiKey: apiKey,
            modelName: modelName
        )
    }

    /// 単発送信（食事推定・接続テスト用）。オンデバイス時はトークン数を0で返す。
    func sendOnce(
        messages: [LLMMessage],
        system: String,
        apiKey: String
    ) async throws -> (text: String, inputTokens: Int, outputTokens: Int) {
        if isOnDevice {
            #if canImport(FoundationModels)
            if #available(iOS 26.0, *) {
                let text = try await OnDeviceLLMService().respond(messages: messages, system: system)
                return (text, 0, 0)
            }
            #endif
            throw LLMError.serverError
        }
        return try await LLMAPIService().sendOnce(
            messages: messages,
            system: system,
            provider: provider,
            apiKey: apiKey,
            modelName: modelName
        )
    }

    private static func unavailableStream() -> AsyncThrowingStream<LLMStreamEvent, Error> {
        AsyncThrowingStream { continuation in
            continuation.finish(throwing: LLMError.serverError)
        }
    }
}
