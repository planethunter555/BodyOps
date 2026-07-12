import SwiftUI
import SwiftData

/// 設定画面のAI関連セクション（プロバイダー・プライバシー・API使用料金）。
/// AI設定はこのビュー内で自動保存されるため、親の保存ボタンには依存しない。
struct AISettingsSections: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \APIUsageRecord.recordedAt, order: .reverse)
    private var allUsageRecords: [APIUsageRecord]
    @AppStorage(AIConsentStorage.key) private var hasAIConsent = false

    @State private var selectedProvider: LLMProvider = .claude
    @State private var modelName: String = ""
    @State private var apiKeyInput: String = ""
    @State private var connectionTestResult: String = ""
    @State private var isTestingConnection = false
    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false
    @State private var isLoadingCurrentValues = false
    @State private var saveError: String?
    @FocusState private var isAPIKeyFocused: Bool

    var body: some View {
        Group {
            llmSection
            aiPrivacySection
            apiCostSection
        }
        .onAppear { loadCurrentValues() }
        .onDisappear {
            if !isLoadingCurrentValues {
                persistAISettingsWithoutAlert()
            }
        }
        .alert("保存エラー", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
            Button("OK") { saveError = nil }
        } message: {
            Text(saveError ?? "")
        }
    }

    // MARK: - LLM Section

    /// 選択可能なプロバイダー。Apple IntelligenceはOSが対応している場合のみ表示する。
    private var selectableProviders: [LLMProvider] {
        LLMProvider.allCases.filter { provider in
            provider != .appleOnDevice || OnDeviceAvailability.check() != .unsupportedOS
        }
    }

    private var llmSection: some View {
        Section {
            Picker("プロバイダー", selection: $selectedProvider) {
                ForEach(selectableProviders, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: selectedProvider) { _, newProvider in
                guard !isLoadingCurrentValues else { return }
                apiKeyInput = KeychainService.shared.load(forProvider: newProvider) ?? ""
                loadModelOptions(for: newProvider, preferredModel: nil)
                persistAISettingsWithoutAlert()
            }

            if selectedProvider == .appleOnDevice {
                onDeviceStatusRow
            } else {
                modelPickerRow

                modelRefreshRow

                VStack(alignment: .leading, spacing: 4) {
                    Text("APIキー")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    SecureField("sk-...", text: $apiKeyInput)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .focused($isAPIKeyFocused)
                        .onSubmit {
                            persistAISettingsWithoutAlert()
                        }
                        .onChange(of: isAPIKeyFocused) { wasFocused, isFocused in
                            if wasFocused && !isFocused {
                                persistAISettingsWithoutAlert()
                            }
                        }
                    Text("APIキーとAI設定は自動保存されます。接続テストは任意です。")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }

                Button {
                    Task { await testConnection() }
                } label: {
                    HStack {
                        Text("接続テスト")
                        if isTestingConnection {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                    }
                }
                .disabled(isTestingConnection || apiKeyInput.isEmpty)

                if !connectionTestResult.isEmpty {
                    Text(connectionTestResult)
                        .font(.caption)
                        .foregroundStyle(connectionTestResult.contains("成功") ? .green : .red)
                }
            }
        } header: {
            Text("AIプロバイダー")
        } footer: {
            if selectedProvider == .appleOnDevice {
                Text("オンデバイスAIは無料で、データが端末外に送信されません。画像解析（チャットの画像添付・食事写真からの推定）には対応していません。")
            } else {
                Text("チャット時は入力内容・添付画像・プロフィール・目標・直近の筋トレ/食事記録を選択中のプロバイダーへ送信します。")
            }
        }
    }

    private var onDeviceStatusRow: some View {
        let availability = OnDeviceAvailability.check()
        return HStack(spacing: 8) {
            Image(systemName: availability.isAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                .foregroundStyle(availability.isAvailable ? .green : .orange)
            Text(availability.statusDescription)
                .font(.subheadline)
        }
    }

    private var modelRefreshRow: some View {
        HStack {
            if let date = ModelListService.shared.lastFetchDate(for: selectedProvider) {
                Text("更新: \(date, format: .dateTime.month().day())")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            } else {
                Text("モデル一覧未取得")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            Spacer()
            Button {
                Task { await refreshModels() }
            } label: {
                if isFetchingModels {
                    ProgressView().scaleEffect(0.7)
                } else {
                    Label("更新", systemImage: "arrow.clockwise")
                        .font(.caption)
                }
            }
            .disabled(isFetchingModels || apiKeyInput.isEmpty)
        }
    }

    @ViewBuilder
    private var modelPickerRow: some View {
        if availableModels.isEmpty {
            HStack {
                Text("モデル")
                Spacer()
                Text("ー")
                    .foregroundStyle(.secondary)
            }
        } else {
            Picker("モデル", selection: $modelName) {
                ForEach(availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .onChange(of: modelName) { _, _ in
                guard !isLoadingCurrentValues else { return }
                persistAISettingsWithoutAlert()
            }
        }
    }

    // MARK: - Privacy Section

    private var aiPrivacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("AIデータ送信", systemImage: "lock.shield")
                    .font(.subheadline.bold())
                Text("AIチャットや食事AI推定では、入力内容・添付画像・プロフィール・目標・制約・直近の筋トレ/食事記録を、選択中のAIプロバイダーへ送信する場合があります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text(selectedProvider == .appleOnDevice
                     ? "処理場所: 端末内（Apple Intelligence・外部送信なし）"
                     : "送信先: \(selectedProvider.displayName)")
                    .font(.caption)
                Text("APIキーは端末内のiOS Keychainに保存され、開発者のサーバーには保存されません。AI同意を取り消しても、通常の記録機能は利用できます。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            HStack {
                Text("AI送信への同意")
                Spacer()
                Text(hasAIConsent ? "同意済み" : "未同意")
                    .foregroundStyle(hasAIConsent ? .green : .secondary)
            }
            if hasAIConsent {
                Button(role: .destructive) {
                    hasAIConsent = false
                } label: {
                    Text("同意を取り消す")
                }
            }
        } header: {
            Text("AIデータ送信とプライバシー")
        }
    }

    // MARK: - Cost Section

    private var apiCostSection: some View {
        let calendar = Calendar.current
        let now = Date()
        let startOfMonth = calendar.date(from: calendar.dateComponents([.year, .month], from: now)) ?? now
        let thisMonthRecords = allUsageRecords.filter { $0.recordedAt >= startOfMonth }
        let totalCost = thisMonthRecords.reduce(0) { $0 + $1.costUSD }

        // Group by day (yyyy-MM-dd)
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        let dayFormatter = DateFormatter()
        dayFormatter.dateFormat = "yyyy-MM-dd"
        var byDay: [(day: String, label: String, cost: Double, calls: Int)] = []
        var seen: [String: Int] = [:]
        for record in thisMonthRecords {
            let key = dayFormatter.string(from: record.recordedAt)
            if let idx = seen[key] {
                byDay[idx] = (day: key, label: byDay[idx].label, cost: byDay[idx].cost + record.costUSD, calls: byDay[idx].calls + 1)
            } else {
                seen[key] = byDay.count
                byDay.append((day: key, label: formatter.string(from: record.recordedAt), cost: record.costUSD, calls: 1))
            }
        }

        return Section {
            if thisMonthRecords.isEmpty {
                Text("今月のAPI使用はありません")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                HStack {
                    Text("今月の合計")
                        .font(.subheadline)
                    Spacer()
                    Text(String(format: "$%.4f", totalCost))
                        .font(.subheadline.monospacedDigit())
                        .foregroundStyle(totalCost > 1.0 ? .orange : .primary)
                }
                ForEach(byDay.prefix(10), id: \.day) { entry in
                    HStack {
                        Text(entry.label)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Text("\(entry.calls)回")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Spacer()
                        Text(String(format: "$%.4f", entry.cost))
                            .font(.caption.monospacedDigit())
                    }
                }
            }
        } header: {
            Text("API使用料金（今月）")
        } footer: {
            Text("概算値です。実際の料金はプロバイダーのダッシュボードで確認してください。")
        }
    }

    // MARK: - Load / Persist

    private func loadCurrentValues() {
        isLoadingCurrentValues = true
        defer { isLoadingCurrentValues = false }

        let setting = LLMSettingsStore.currentIfExists(in: modelContext)
        if let setting {
            selectedProvider = setting.provider
        }
        apiKeyInput = KeychainService.shared.load(forProvider: selectedProvider) ?? ""
        loadModelOptions(for: selectedProvider, preferredModel: setting?.modelName)

        // キャッシュが古い場合、APIキーがあれば自動でバックグラウンド更新
        if !ModelListService.shared.isCacheFresh(for: selectedProvider) && !apiKeyInput.isEmpty {
            Task { await refreshModels() }
        }
    }

    @MainActor
    private func refreshModels() async {
        isFetchingModels = true
        let key = apiKeyInput.isEmpty ? (KeychainService.shared.load(forProvider: selectedProvider) ?? "") : apiKeyInput
        let fetched = await ModelListService.shared.fetchModelsIgnoringCache(for: selectedProvider, apiKey: key)
        availableModels = fetched
        if availableModels.contains(modelName) {
            // Keep the user's current selection.
        } else if let saved = LLMSettingsStore.currentIfExists(in: modelContext)?.modelName,
                  availableModels.contains(saved) {
            modelName = saved
        } else {
            modelName = availableModels.first ?? ""
        }
        isFetchingModels = false
    }

    private func testConnection() async {
        guard !apiKeyInput.isEmpty else {
            connectionTestResult = "❌ APIキーが入力されていません"
            return
        }
        do {
            try persistLLMSetting()
        } catch {
            connectionTestResult = "❌ APIキーの保存に失敗しました"
            return
        }
        isTestingConnection = true
        connectionTestResult = ""
        let effectiveModel = modelName.isEmpty ? selectedProvider.defaultModel : modelName
        let message = LLMMessage(role: "user", content: "Reply with OK only.")
        do {
            var response = ""
            for try await chunk in LLMAPIService().sendMessage(
                messages: [message],
                system: "",
                provider: selectedProvider,
                apiKey: apiKeyInput,
                modelName: effectiveModel
            ) {
                response += chunk
            }
            connectionTestResult = response.isEmpty ? "⚠️ 応答が空です" : "✓ 接続成功。AI設定を保存しました。"
        } catch let error as LLMError {
            switch error {
            case .unauthorized: connectionTestResult = "❌ APIキーが無効です"
            case .rateLimited: connectionTestResult = "⚠️ レート制限中。しばらく待ってください"
            case .badRequest(let status): connectionTestResult = "❌ リクエストエラー(コード\(status))。モデルを変更してみてください"
            case .serverError: connectionTestResult = "❌ サーバーエラー"
            case .networkError: connectionTestResult = "❌ ネットワークエラー"
            case .contextTooLong: connectionTestResult = "❌ コンテキスト超過"
            }
        } catch {
            connectionTestResult = "❌ 接続失敗"
        }
        isTestingConnection = false
    }

    private func persistAISettingsWithoutAlert() {
        do {
            try persistLLMSetting()
        } catch {
            saveError = "AI設定の保存に失敗しました"
        }
    }

    private func persistLLMSetting() throws {
        let llmSetting = try LLMSettingsStore.current(in: modelContext)
        llmSetting.provider = selectedProvider
        llmSetting.modelName = modelName
        llmSetting.updatedAt = Date()

        try KeychainService.shared.save(apiKey: apiKeyInput, forProvider: selectedProvider)
        try modelContext.save()
    }

    private func loadModelOptions(for provider: LLMProvider, preferredModel: String?) {
        // オンデバイスはモデル選択なし（固定）
        if provider == .appleOnDevice {
            availableModels = []
            modelName = provider.defaultModel
            return
        }
        availableModels = ModelListService.shared.cachedModels(for: provider)
        if let preferredModel, availableModels.contains(preferredModel) {
            modelName = preferredModel
        } else if !availableModels.isEmpty {
            modelName = availableModels.first ?? ""
        } else {
            modelName = ""
        }
    }
}
