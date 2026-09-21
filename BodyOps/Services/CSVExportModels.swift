import Foundation

/// CSV書き出し用の筋トレセットスナップショット。SwiftDataモデルはMainActor上でこの型に変換してから
/// バックグラウンドへ渡す（アクター境界をまたいでSwiftDataモデルを直接渡さないため）。
struct WorkoutSetCSVRow: Sendable, Equatable {
    let sessionId: UUID
    let sessionDate: Date
    let exerciseName: String
    let category: String
    let setNumber: Int
    let weightKg: Double
    let reps: Int
    let volume: Double
    let memo: String
}

/// CSV書き出し用の食事記録スナップショット。
struct MealRecordCSVRow: Sendable, Equatable {
    let mealId: UUID
    let recordedAt: Date
    let mealType: String
    let mealDescription: String
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double
}
