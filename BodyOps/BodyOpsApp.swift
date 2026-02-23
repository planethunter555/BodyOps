import SwiftUI
import SwiftData

@main
struct BodyOpsApp: App {
    let container: ModelContainer = {
        let schema = Schema([
            UserProfile.self,
            Exercise.self,
            WorkoutSession.self,
            WorkoutSet.self,
            ChatMessage.self,
            MealRecord.self,
            NotificationSetting.self,
            LLMSetting.self
        ])
        // swiftlint:disable:next force_try
        return try! ModelContainer(for: schema)
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .onAppear {
                    let context = container.mainContext
                    let service = ExercisePresetService(context: context)
                    try? service.seedIfNeeded()
                }
        }
        .modelContainer(container)
    }
}
