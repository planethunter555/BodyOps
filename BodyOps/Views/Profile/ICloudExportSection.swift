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
    }

    private var lastExportText: String {
        guard let date = service.status.lastExportDate else { return "未実行" }
        return date.formatted(date: .abbreviated, time: .shortened)
    }
}
