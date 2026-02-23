import SwiftUI
import SwiftData

@main
struct BodyOpsApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
        }
        .modelContainer(for: [
            UserProfile.self,
            Exercise.self,
            WorkoutSession.self,
            WorkoutSet.self,
            ChatMessage.self,
            MealRecord.self,
            NotificationSetting.self,
            LLMSetting.self
        ])
    }
}
