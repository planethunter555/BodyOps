import Foundation

final class ModelListService: @unchecked Sendable {
    static let shared = ModelListService()
    private let defaults = UserDefaults.standard
    private let cacheValidityDays = 30

    // MARK: - Public

    /// キャッシュが新鮮なら即返す。古い or 空なら API フェッチしてキャッシュ更新。
    func fetchModels(for provider: LLMProvider, apiKey: String) async -> [String] {
        if isCacheFresh(for: provider), let cached = loadCache(for: provider), !cached.isEmpty {
            return cached
        }
        return await fetchModelsIgnoringCache(for: provider, apiKey: apiKey)
    }

    /// 更新ボタン用：キャッシュを無視して必ずAPIから取得する
    func fetchModelsIgnoringCache(for provider: LLMProvider, apiKey: String) async -> [String] {
        if let fetched = try? await fetchFromAPI(provider: provider, apiKey: apiKey) {
            let filtered = filter(models: fetched, for: provider)
            if !filtered.isEmpty {
                saveCache(filtered, for: provider)
                return filtered
            }
        }
        return loadCache(for: provider) ?? provider.models
    }

    /// キャッシュがあればそれを返す（非同期不要な初期表示用）
    func cachedModels(for provider: LLMProvider) -> [String] {
        loadCache(for: provider) ?? provider.models
    }

    func isCacheFresh(for provider: LLMProvider) -> Bool {
        guard let date = defaults.object(forKey: lastFetchedKey(for: provider)) as? Date else { return false }
        let days = Calendar.current.dateComponents([.day], from: date, to: Date()).day ?? 999
        return days < cacheValidityDays
    }

    func lastFetchDate(for provider: LLMProvider) -> Date? {
        defaults.object(forKey: lastFetchedKey(for: provider)) as? Date
    }

    // MARK: - API Fetch

    private func fetchFromAPI(provider: LLMProvider, apiKey: String) async throws -> [String] {
        switch provider {
        case .claude:  return try await fetchClaudeModels(apiKey: apiKey)
        case .openai:  return try await fetchOpenAIModels(apiKey: apiKey)
        case .gemini:  return try await fetchGeminiModels(apiKey: apiKey)
        }
    }

    private func fetchClaudeModels(apiKey: String) async throws -> [String] {
        // swiftlint:disable:next force_unwrapping
        var request = URLRequest(url: URL(string: "https://api.anthropic.com/v1/models")!)
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["id"] as? String }
    }

    private func fetchOpenAIModels(apiKey: String) async throws -> [String] {
        // swiftlint:disable:next force_unwrapping
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, _) = try await URLSession.shared.data(for: request)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else { return [] }
        // created (Unix timestamp) で降順ソートしてIDを返す
        return models
            .compactMap { dict -> (id: String, created: Int)? in
                guard let id = dict["id"] as? String,
                      let created = dict["created"] as? Int else { return nil }
                return (id, created)
            }
            .sorted { $0.created > $1.created }
            .map { $0.id }
    }

    private func fetchGeminiModels(apiKey: String) async throws -> [String] {
        let urlString = "https://generativelanguage.googleapis.com/v1beta/models?key=\(apiKey)"
        // swiftlint:disable:next force_unwrapping
        let (data, _) = try await URLSession.shared.data(for: URLRequest(url: URL(string: urlString)!))
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        // "name" は "models/gemini-2.0-flash" 形式なので prefix を除去
        return models.compactMap { ($0["name"] as? String)?.replacingOccurrences(of: "models/", with: "") }
    }

    // MARK: - Filtering (~5 representative models)

    private func filter(models: [String], for provider: LLMProvider) -> [String] {
        switch provider {
        case .claude:  return filterClaude(models)
        case .openai:  return filterOpenAI(models)
        case .gemini:  return filterGemini(models)
        }
    }

    private func filterClaude(_ models: [String]) -> [String] {
        // claude-2.x / claude-instant 除外、新しいものを優先（降順ソート）
        let relevant = models.filter {
            $0.hasPrefix("claude-") &&
            !$0.contains("instant") &&
            !$0.hasPrefix("claude-2") &&
            !$0.hasPrefix("claude-1")
        }
        return Array(relevant.sorted(by: >).prefix(5))
    }

    private func filterOpenAI(_ models: [String]) -> [String] {
        // チャット用モデルのみ（音声・埋め込み・画像生成系を除外）
        let relevant = models.filter {
            !$0.contains("instruct") &&
            !$0.contains("realtime") &&
            !$0.contains("audio") &&
            !$0.contains("embedding") &&
            !$0.contains("whisper") &&
            !$0.contains("tts") &&
            !$0.contains("dall-e") &&
            !$0.contains("moderation") &&
            !$0.contains("babbage") &&
            !$0.contains("davinci")
        }
        // fetchOpenAIModels で既に created 降順になっているので上位10件を返す
        return Array(relevant.prefix(10))
    }

    private func filterGemini(_ models: [String]) -> [String] {
        // embedding / aqa / vision 専用モデルを除外
        let relevant = models.filter {
            $0.hasPrefix("gemini-") &&
            !$0.contains("embedding") &&
            !$0.contains("aqa")
        }
        return Array(relevant.sorted(by: >).prefix(5))
    }

    // MARK: - Cache

    private func cacheKey(for provider: LLMProvider) -> String { "modelList_\(provider.rawValue)" }
    private func lastFetchedKey(for provider: LLMProvider) -> String { "modelListFetched_\(provider.rawValue)" }

    private func loadCache(for provider: LLMProvider) -> [String]? {
        defaults.stringArray(forKey: cacheKey(for: provider))
    }

    private func saveCache(_ models: [String], for provider: LLMProvider) {
        defaults.set(models, forKey: cacheKey(for: provider))
        defaults.set(Date(), forKey: lastFetchedKey(for: provider))
    }
}
