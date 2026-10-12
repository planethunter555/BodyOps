import SwiftUI
import SwiftData

/// 設定画面のiCloud CSV書き出しセクション（自己完結）
struct ICloudExportSection: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable private var service = ICloudExportService.shared
    @State private var isExporting = false

    var body: some View {
        Section("データ書き出し") {
            Toggle("iCloudへ自動書き出し", isOn: $service.isEnabled)

            LabeledContent("iCloud") {
                Text(service.status.isICloudAvailable ? "利用可能" : "利用不可")
                    .foregroundStyle(service.status.isICloudAvailable ? .primary : .secondary)
            }
            LabeledContent("最終書き出し") {
                Text(lastExportText)
                    .foregroundStyle(.secondary)
            }
            LabeledContent("筋トレ記録") {
                Text("\(service.status.lastWorkoutRowCount)件")
                    .foregroundStyle(.secondary)
            }
            LabeledContent("食事記録") {
                Text("\(service.status.lastMealRowCount)件")
                    .foregroundStyle(.secondary)
            }

            Button {
                Task {
                    isExporting = true
                    await service.exportNow(context: modelContext)
                    isExporting = false
                }
            } label: {
                HStack {
                    Text("今すぐ書き出す")
                    if isExporting {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isExporting)

            Text("iCloud Drive内の「BodyOps」フォルダにbodyops_workouts.csvとbodyops_meals.csvとして書き出します")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .task { await service.refreshAvailability() }

        healthKitSection
    }

    // MARK: - Apple ヘルスケア

    @ViewBuilder
    private var healthKitSection: some View {
        Section("Apple ヘルスケア") {
            Toggle("Apple ヘルスケアから読み込む", isOn: $service.isHealthKitImportEnabled)
                .disabled(!service.status.isHealthKitAvailable)
                .onChange(of: service.isHealthKitImportEnabled) { _, isOn in
                    // 初回ONで権限ダイアログを出す。読み取りのみを要求する。
                    guard isOn else { return }
                    Task { await service.requestHealthKitAuthorization() }
                }

            if !service.status.isHealthKitAvailable {
                Text("この端末ではApple ヘルスケアを利用できません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            // 権限要求に失敗したら黙って終わらず必ず画面に出す。
            if let message = service.status.healthKitErrorMessage {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.red)
            }

            if service.isHealthKitImportEnabled {
                LabeledContent("睡眠") {
                    Text("\(service.status.lastHealthSleepRowCount)区間")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("日次サマリー") {
                    Text("\(service.status.lastHealthDailyRowCount)件")
                        .foregroundStyle(.secondary)
                }
                LabeledContent("体組成") {
                    Text("\(service.status.lastHealthBodyRowCount)件")
                        .foregroundStyle(.secondary)
                }

                // HealthKit は仕様上「読み取りを許可されているか」をアプリから判定できない
                // （プライバシー保護のため、拒否とデータ0件が区別できない）。
                // そのため0件のときは断定せず、両方の可能性を示す文言にする。
                if hasNoHealthRows {
                    Text("データが無いか、許可されていません。「設定」>「プライバシーとセキュリティ」>「ヘルスケア」からBody Opsの読み取りを確認してください。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Text("睡眠・安静時心拍・歩数・距離・消費エネルギー・階数・体組成を直近365日分読み込み、bodyops_health_sleep.csv / bodyops_health_daily.csv / bodyops_health_body.csv として上の「今すぐ書き出す」で一緒に書き出します。読み取りのみで、ヘルスケアには書き込みません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var hasNoHealthRows: Bool {
        service.status.lastHealthSleepRowCount == 0
            && service.status.lastHealthDailyRowCount == 0
            && service.status.lastHealthBodyRowCount == 0
    }

    private var lastExportText: String {
        guard let date = service.status.lastExportDate else { return "未実行" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
