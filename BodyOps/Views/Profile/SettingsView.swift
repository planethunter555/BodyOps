import SwiftUI
import SwiftData

/// 設定画面のシェル。AI関連は AISettingsSections、通知は NotificationSettingsSection、
/// カスタム種目は ExerciseManagementSection に分割されている。
struct SettingsView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var profiles: [UserProfile]
    @Query private var notificationSettings: [NotificationSetting]

    @State private var height: String = ""
    @State private var weight: String = ""
    @State private var bodyFat: String = ""
    @State private var targetMuscleMass: String = ""
    @State private var targetBodyFat: String = ""
    @State private var weeklyDays: Int = 3
    @State private var goals: String = ""
    @State private var constraints: String = ""
    @State private var systemPromptPrefix: String = ""

    @State private var notificationsEnabled = false
    @State private var selectedWeekdays: Set<Int> = []
    @State private var notificationTime: Date = Calendar.current.date(
        bySettingHour: 20, minute: 0, second: 0, of: Date()
    ) ?? Date()
    @State private var showSaveAlert = false
    @State private var saveError: String?

    var currentProfile: UserProfile? { profiles.first }

    var body: some View {
        NavigationStack {
            Form {
                profileSection
                goalSection
                AISettingsSections()
                promptSection
                NotificationSettingsSection(
                    notificationsEnabled: $notificationsEnabled,
                    selectedWeekdays: $selectedWeekdays,
                    notificationTime: $notificationTime
                )
                ExerciseManagementSection()
                ICloudExportSection()
            }
            .scrollDismissesKeyboard(.immediately)
            .keyboardDoneButton()
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

    // MARK: - Sections

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

    // MARK: - Load / Save

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
}
