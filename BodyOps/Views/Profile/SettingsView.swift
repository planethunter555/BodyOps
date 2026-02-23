import SwiftUI
import SwiftData

struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var llmSettings: [LLMSetting]
    @Query(filter: #Predicate<Exercise> { !$0.isPreset }, sort: \Exercise.name)
    private var customExercises: [Exercise]

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

    @State private var notificationsEnabled = false
    @State private var showSaveAlert = false

    var currentProfile: UserProfile? { profiles.first }
    var currentLLMSetting: LLMSetting? { llmSettings.first }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                goalSection
                llmSection
                promptSection
                notificationSection
                customExerciseSection
            }
            .navigationTitle("設定")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear { loadCurrentValues() }
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveSettings() }
                }
            }
            .alert("保存しました", isPresented: $showSaveAlert) {
                Button("OK") {}
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
        Section("AIプロバイダー") {
            Picker("プロバイダー", selection: $selectedProvider) {
                ForEach(LLMProvider.allCases, id: \.self) { provider in
                    Text(provider.displayName).tag(provider)
                }
            }
            .onChange(of: selectedProvider) { _, newProvider in
                modelName = newProvider.defaultModel
                apiKeyInput = KeychainService.shared.load(forProvider: newProvider) ?? ""
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("モデル名")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TextField(selectedProvider.defaultModel, text: $modelName)
            }

            VStack(alignment: .leading, spacing: 4) {
                Text("APIキー")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                SecureField("sk-...", text: $apiKeyInput)
                    .autocorrectionDisabled()
                    .textInputAutocapitalization(.never)
            }

            Button {
                saveApiKey()
                testConnection()
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
                .onChange(of: notificationsEnabled) { _, _ in }
        }
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
            modelName = setting.modelName
        }
        apiKeyInput = KeychainService.shared.load(forProvider: selectedProvider) ?? ""
    }

    private func saveApiKey() {
        try? KeychainService.shared.save(apiKey: apiKeyInput, forProvider: selectedProvider)
    }

    private func testConnection() {
        isTestingConnection = true
        connectionTestResult = ""
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
            isTestingConnection = false
            connectionTestResult = apiKeyInput.isEmpty
                ? "APIキーが入力されていません"
                : "接続テストはアプリ内チャットで確認できます"
        }
    }

    private func saveSettings() {
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

        saveApiKey()

        try? modelContext.save()
        showSaveAlert = true
    }

    private func deleteCustomExercises(at indexSet: IndexSet) {
        for index in indexSet {
            modelContext.delete(customExercises[index])
        }
        try? modelContext.save()
    }
}
