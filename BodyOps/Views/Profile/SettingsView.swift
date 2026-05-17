import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var llmSettings: [LLMSetting]
    @Query private var notificationSettings: [NotificationSetting]
    @Query(filter: #Predicate<Exercise> { !$0.isPreset }, sort: \Exercise.name)
    private var customExercises: [Exercise]
    @Query(sort: \APIUsageRecord.recordedAt, order: .reverse)
    private var allUsageRecords: [APIUsageRecord]

    @State private var height: String = ""
    @State private var weight: String = ""
    @State private var bodyFat: String = ""
    @State private var targetMuscleMass: String = ""
    @State private var targetBodyFat: String = ""
    @State private var weeklyDays: Int = 3
    @State private var goals: String = ""
    @State private var constraints: String = ""
    @State private var systemPromptPrefix: String = ""

    @State private var selectedProvider: LLMProvider = .claude
    @State private var modelName: String = ""
    @State private var apiKeyInput: String = ""
    @State private var connectionTestResult: String = ""
    @State private var isTestingConnection = false

    @State private var availableModels: [String] = []
    @State private var isFetchingModels = false

    @State private var notificationsEnabled = false
    @State private var selectedWeekdays: Set<Int> = []
    @State private var notificationTime: Date = Calendar.current.date(
        bySettingHour: 20, minute: 0, second: 0, of: Date()
    ) ?? Date()
    @State private var showSaveAlert = false
    @State private var saveError: String?
    @AppStorage(AIConsentStorage.key) private var hasAIConsent = false

    var currentProfile: UserProfile? { profiles.first }
    var currentLLMSetting: LLMSetting? { llmSettings.first }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                goalSection
                llmSection
                aiPrivacySection
                apiCostSection
                promptSection
                notificationSection
                customExerciseSection
            }
            .scrollDismissesKeyboard(.immediately)
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadCurrentValues() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") {
                        UIApplication.shared.sendAction(
                            #selector(UIResponder.resignFirstResponder),
                            to: nil, from: nil, for: nil
                        )
                        Task { await saveSettings() }
                    }
                }
            }
            .alert("保存しました", isPresented: $showSaveAlert) {
                Button("OK") {}
            }
            .alert("保存エラー", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK") { saveError = nil }
            } message: {
                Text(saveError ?? "")
            }
        }
    }

    private var profileSection: some View {
        Section("プロフィール") {
            HStack {
                Text("身長")
                Spacer()
                TextField("170", text: $height)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("cm")
            }
            HStack {
                Text("体重")
                Spacer()
                TextField("70", text: $weight)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("kg")
            }
            HStack {
                Text("体脂肪率")
                Spacer()
                TextField("20", text: $bodyFat)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("%")
            }
        }
    }

    private var goalSection: some View {
        Section("目標") {
            HStack {
                Text("目標筋肉量")
                Spacer()
                TextField("60", text: $targetMuscleMass)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("kg")
            }
            HStack {
                Text("目標体脂肪率")
                Spacer()
                TextField("15", text: $targetBodyFat)
                    .keyboardType(.decimalPad)
                    .multilineTextAlignment(.trailing)
                    .frame(width: 80)
                Text("%")
            }
            Stepper("週 \(weeklyDays) 日", value: $weeklyDays, in: 1...7)
            VStack(alignment: .leading, spacing: 4) {
                Text("目標・制約・要望")
                    .font(.subheadline)
                TextField("例：バルクアップしたい、膝が悪いので無理できない", text: $constraints, axis: .vertical)
                    .lineLimit(3...)
                    .font(.subheadline)
            }
        }
    }

    private var llmSection: some View {
        Section {
            Picker("プロバイダー", selection: $selectedProvider) {
                ForEach(LLMProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: selectedProvider) { _, newProvider in
                availableModels = ModelListService.shared.cachedModels(for: newProvider)
                modelName = availableModels.first ?? newProvider.defaultModel
                apiKeyInput = KeychainService.shared.load(forProvider: newProvider) ?? ""
            }

            Picker("モデル", selection: $modelName) {
                ForEach(availableModels, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .disabled(availableModels.isEmpty)

            modelRefreshRow

            VStack(alignment: .leading, spacing: 4) {
                Text("APIキー")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("sk-...", text: $apiKeyInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Button {
                try? KeychainService.shared.save(apiKey: apiKeyInput, forProvider: selectedProvider)
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
        } header: {
            Text("AIプロバイダー")
        } footer: {
            Text("チャット時は入力内容・添付画像・プロフィール・目標・直近の筋トレ/食事記録を選択中のプロバイダーへ送信します。")
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

    private var aiPrivacySection: some View {
        Section {
            VStack(alignment: .leading, spacing: 10) {
                Label("AIデータ送信", systemImage: "lock.shield")
                    .font(.subheadline.bold())
                Text("AIチャットや食事AI推定では、入力内容・添付画像・プロフィール・目標・制約・直近の筋トレ/食事記録を、選択中のAIプロバイダーへ送信する場合があります。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Text("送信先: \(selectedProvider.displayName)")
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

    private var promptSection: some View {
        Section("AIへのPre-fixプロンプト") {
            TextField(
                "例：あなたはプロのトレーナーです。...",
                text: $systemPromptPrefix,
                axis: .vertical
            )
            .lineLimit(4...)
            Text("このプロンプトはAIアドバイスの全チャットに先頭付与されます")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var notificationSection: some View {
        Section("通知") {
            Toggle("トレーニングリマインダー", isOn: $notificationsEnabled)
            if notificationsEnabled {
                weekdayPickerRow
                DatePicker("通知時刻", selection: $notificationTime, displayedComponents: .hourAndMinute)
            }
        }
    }

    private var weekdayPickerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("曜日")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([(1, "日"), (2, "月"), (3, "火"), (4, "水"), (5, "木"), (6, "金"), (7, "土")], id: \.0) { day, label in
                    weekdayButton(day: day, label: label)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func weekdayButton(day: Int, label: String) -> some View {
        let selected = selectedWeekdays.contains(day)
        return Button {
            if selectedWeekdays.contains(day) {
                selectedWeekdays.remove(day)
            } else {
                selectedWeekdays.insert(day)
            }
        } label: {
            Text(label)
                .font(.caption.bold())
                .frame(width: 32, height: 32)
                .background(selected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private var customExerciseSection: some View {
        Section("カスタム種目") {
            if customExercises.isEmpty {
                Text("カスタム種目はありません")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(customExercises) { exercise in
                    HStack {
                        Text(exercise.name)
                        Spacer()
                        Text(exercise.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { indexSet in
                    deleteCustomExercises(at: indexSet)
                }
            }
        }
    }

    private func loadCurrentValues() {
        if let profile = currentProfile {
            height = String(profile.height)
            weight = String(profile.weight)
            bodyFat = String(profile.bodyFatPercentage)
            targetMuscleMass = String(profile.targetMuscleMass)
            targetBodyFat = String(profile.targetBodyFat)
            weeklyDays = profile.weeklyWorkoutDays
            goals = profile.goals
            constraints = profile.constraints
            systemPromptPrefix = profile.systemPromptPrefix
        }
        if let setting = currentLLMSetting {
            selectedProvider = setting.provider
        }
        // キャッシュからモデル一覧を即時ロード
        availableModels = ModelListService.shared.cachedModels(for: selectedProvider)
        if let setting = currentLLMSetting {
            modelName = availableModels.contains(setting.modelName)
                ? setting.modelName
                : (availableModels.first ?? selectedProvider.defaultModel)
        }
        apiKeyInput = KeychainService.shared.load(forProvider: selectedProvider) ?? ""
        // キャッシュが古い場合、APIキーがあれば自動でバックグラウンド更新
        if !ModelListService.shared.isCacheFresh(for: selectedProvider) && !apiKeyInput.isEmpty {
            Task { await refreshModels() }
        }
        if let notifSetting = notificationSettings.first {
            notificationsEnabled = notifSetting.isEnabled
            selectedWeekdays = Set(notifSetting.weekdays)
            notificationTime = Calendar.current.date(
                bySettingHour: notifSetting.hour,
                minute: notifSetting.minute,
                second: 0,
                of: Date()
            ) ?? notificationTime
        }
    }

    @MainActor
    private func refreshModels() async {
        isFetchingModels = true
        let key = apiKeyInput.isEmpty ? (KeychainService.shared.load(forProvider: selectedProvider) ?? "") : apiKeyInput
        let fetched = await ModelListService.shared.fetchModelsIgnoringCache(for: selectedProvider, apiKey: key)
        availableModels = fetched
        if !availableModels.contains(modelName) {
            modelName = availableModels.first ?? selectedProvider.defaultModel
        }
        isFetchingModels = false
    }

    private func testConnection() async {
        guard !apiKeyInput.isEmpty else {
            connectionTestResult = "❌ APIキーが入力されていません"
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
            connectionTestResult = response.isEmpty ? "⚠️ 応答が空です" : "✓ 接続成功"
        } catch let error as LLMError {
            switch error {
            case .unauthorized: connectionTestResult = "❌ APIキーが無効です"
            case .rateLimited: connectionTestResult = "⚠️ レート制限中。しばらく待ってください"
            case .serverError: connectionTestResult = "❌ サーバーエラー"
            case .networkError: connectionTestResult = "❌ ネットワークエラー"
            }
        } catch {
            connectionTestResult = "❌ 接続失敗"
        }
        isTestingConnection = false
    }

    private func saveSettings() async {
        let profile: UserProfile
        if let existing = currentProfile {
            profile = existing
        } else {
            profile = UserProfile()
            modelContext.insert(profile)
        }
        profile.height = Double(height) ?? profile.height
        profile.weight = Double(weight) ?? profile.weight
        profile.bodyFatPercentage = Double(bodyFat) ?? profile.bodyFatPercentage
        profile.targetMuscleMass = Double(targetMuscleMass) ?? profile.targetMuscleMass
        profile.targetBodyFat = Double(targetBodyFat) ?? profile.targetBodyFat
        profile.weeklyWorkoutDays = weeklyDays
        profile.goals = goals
        profile.constraints = constraints
        profile.systemPromptPrefix = systemPromptPrefix

        let llmSetting: LLMSetting
        if let existing = currentLLMSetting {
            llmSetting = existing
        } else {
            llmSetting = LLMSetting(provider: selectedProvider, modelName: modelName)
            modelContext.insert(llmSetting)
        }
        llmSetting.provider = selectedProvider
        llmSetting.modelName = modelName.isEmpty ? selectedProvider.defaultModel : modelName
        llmSetting.apiKey = selectedProvider.rawValue

        do {
            try KeychainService.shared.save(apiKey: apiKeyInput, forProvider: selectedProvider)
        } catch {
            saveError = "APIキーの保存に失敗しました"
            return
        }

        await saveNotificationSetting()
        guard saveError == nil else { return }

        do {
            try modelContext.save()
            showSaveAlert = true
        } catch {
            saveError = "設定の保存に失敗しました"
        }
    }

    private func saveNotificationSetting() async {
        let notifSetting: NotificationSetting
        if let existing = notificationSettings.first {
            notifSetting = existing
        } else {
            notifSetting = NotificationSetting()
            modelContext.insert(notifSetting)
        }
        let components = Calendar.current.dateComponents([.hour, .minute], from: notificationTime)
        notifSetting.isEnabled = notificationsEnabled
        notifSetting.weekdays = Array(selectedWeekdays)
        notifSetting.hour = components.hour ?? 20
        notifSetting.minute = components.minute ?? 0

        // Extract value types before async boundary (Swift 6 concurrency)
        let isEnabled = notifSetting.isEnabled
        let weekdays = notifSetting.weekdays
        let hour = notifSetting.hour
        let minute = notifSetting.minute

        let service = NotificationService()
        if isEnabled {
            let granted = (try? await service.requestAuthorization()) ?? false
            if !granted {
                saveError = "通知が許可されていません。設定アプリ → BodyOps → 通知 で許可してください。"
                return
            }
        }
        do {
            try await service.scheduleWeekdays(isEnabled: isEnabled, weekdays: weekdays, hour: hour, minute: minute)
        } catch {
            saveError = "通知のスケジュール設定に失敗しました"
        }
    }

    private func deleteCustomExercises(at indexSet: IndexSet) {
        for index in indexSet {
            modelContext.delete(customExercises[index])
        }
        try? modelContext.save()
    }
}
