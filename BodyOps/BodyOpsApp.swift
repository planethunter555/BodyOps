import SwiftUI
import SwiftData

@main
struct BodyOpsApp: App {
    private let container: ModelContainer?
    private let initError: String?

    init() {
        let schema = Schema([
            UserProfile.self,
            Exercise.self,
            WorkoutSession.self,
            WorkoutSet.self,
            ChatMessage.self,
            MealRecord.self,
            NotificationSetting.self,
            LLMSetting.self,
            APIUsageRecord.self
        ])
        do {
            container = try ModelContainer(for: schema)
            initError = nil
        } catch {
            container = nil
            initError = error.localizedDescription
        }
    }

    var body: some Scene {
        WindowGroup {
            if let c = container {
                ContentView()
                    .onAppear {
                        let service = ExercisePresetService(context: c.mainContext)
                        try? service.seedIfNeeded()
                    }
                    .modelContainer(c)
            } else {
                DataErrorView(message: initError ?? "不明なエラー")
            }
        }
    }
}

private struct DataErrorView: View {
    let message: String

    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.orange)
            Text("データベースエラー")
                .font(.title2.bold())
            Text("アプリのデータを読み込めませんでした。アプリを再インストールしてください。")
                .multilineTextAlignment(.center)
                .foregroundStyle(.secondary)
            Text(message)
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .padding(32)
    }
}
