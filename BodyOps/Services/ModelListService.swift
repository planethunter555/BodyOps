import Foundation

final class ModelListService: @unchecked Sendable {
    static let shared = ModelListService()
    private let defaults = UserDefaults.standard
    private let cacheValidityDays = 30
    private let cacheVersion = 2

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
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["data"] as? [[String: Any]] else { return [] }
        return models.compactMap { $0["id"] as? String }
    }

    private func fetchOpenAIModels(apiKey: String) async throws -> [String] {
        // swiftlint:disable:next force_unwrapping
        var request = URLRequest(url: URL(string: "https://api.openai.com/v1/models")!)
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        let (data, response) = try await URLSession.shared.data(for: request)
        try validate(response: response)
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
        let (data, response) = try await URLSession.shared.data(for: URLRequest(url: URL(string: urlString)!))
        try validate(response: response)
        guard let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let models = json["models"] as? [[String: Any]] else { return [] }
        return models.compactMap { model in
            guard let methods = model["supportedGenerationMethods"] as? [String],
                  methods.contains("generateContent"),
                  let name = model["name"] as? String else { return nil }
            return name.replacingOccurrences(of: "models/", with: "")
        }
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
        // API order is newest first. Keep current Messages API models and remove legacy aliases.
        let relevant = models.filter {
            $0.hasPrefix("claude-") &&
            !$0.contains("instant") &&
            !$0.contains("latest") &&
            !$0.contains("thinking") &&
            !$0.hasPrefix("claude-2") &&
            !$0.hasPrefix("claude-1")
        }
        return Array(relevant.prefix(8))
    }

    private func filterOpenAI(_ models: [String]) -> [String] {
        // /v1/models does not expose endpoint capability, so keep known Chat Completions families.
        let relevant = models.filter {
            isAllowedOpenAIChatModel($0)
        }
        // fetchOpenAIModels で既に created 降順になっているので上位10件を返す
        return Array(relevant.prefix(10))
    }

    private func filterGemini(_ models: [String]) -> [String] {
        // Only generation-capable Gemini models reach this point. Prefer stable text/vision chat models.
        let relevant = models.filter {
            $0.hasPrefix("gemini-") &&
            !$0.contains("latest") &&
            !$0.contains("preview") &&
            !$0.contains("exp") &&
            !$0.contains("live") &&
            !$0.contains("tts") &&
            !$0.contains("image") &&
            !$0.contains("embedding") &&
            !$0.contains("aqa")
        }
        return Array(relevant.sorted(by: >).prefix(8))
    }

    // MARK: - Cache

    private func cacheKey(for provider: LLMProvider) -> String { "modelListV\(cacheVersion)_\(provider.rawValue)" }
    private func lastFetchedKey(for provider: LLMProvider) -> String { "modelListFetchedV\(cacheVersion)_\(provider.rawValue)" }

    private func loadCache(for provider: LLMProvider) -> [String]? {
        guard let cached = defaults.stringArray(forKey: cacheKey(for: provider)) else { return nil }
        let filtered = filter(models: cached, for: provider)
        return filtered.isEmpty ? nil : filtered
    }

    private func saveCache(_ models: [String], for provider: LLMProvider) {
        defaults.set(models, forKey: cacheKey(for: provider))
        defaults.set(Date(), forKey: lastFetchedKey(for: provider))
    }

    private func validate(response: URLResponse) throws {
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    private func isAllowedOpenAIChatModel(_ model: String) -> Bool {
        let blockedTerms = [
            "audio", "realtime", "embedding", "whisper", "tts", "dall-e",
            "moderation", "babbage", "davinci", "instruct", "transcribe",
            "search-preview", "image", "vision-preview"
        ]
        guard !blockedTerms.contains(where: { model.contains($0) }) else { return false }
        return model == "chatgpt-4o-latest" ||
            model.hasPrefix("gpt-5") ||
            model.hasPrefix("gpt-4.1") ||
            model.hasPrefix("gpt-4o")
    }
}
