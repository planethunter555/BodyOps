import Foundation
import SwiftData
import SwiftUI

@Observable
final class TodayViewModel {
    var selectedDate: Date = Calendar.current.startOfDay(for: Date())

    var workoutSessions: [WorkoutSession] = []
    var mealRecords: [MealRecord] = []

    var firstWorkoutDate: Date? = nil
    var totalSessionCount: Int = 0
    var userGoal: String = ""

    var showWorkoutSheet = false
    var showMealSheet = false

    private var context: ModelContext?

    func setup(context: ModelContext) {
        self.context = context
        fetchData()
    }

    func goToPreviousDay() {
        selectedDate = Calendar.current.date(byAdding: .day, value: -1, to: selectedDate) ?? selectedDate
        fetchData()
    }

    func goToNextDay() {
        let next = Calendar.current.date(byAdding: .day, value: 1, to: selectedDate) ?? selectedDate
        if Calendar.current.startOfDay(for: next) <= Calendar.current.startOfDay(for: Date()) {
            selectedDate = next
            fetchData()
        }
    }

    func fetchData() {
        guard let context else { return }
        let start = selectedDate
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start

        let sessionDescriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        let mealDescriptor = FetchDescriptor<MealRecord>(
            predicate: #Predicate { $0.recordedAt >= start && $0.recordedAt < end },
            sortBy: [SortDescriptor(\.recordedAt)]
        )
        workoutSessions = (try? context.fetch(sessionDescriptor)) ?? []
        mealRecords = (try? context.fetch(mealDescriptor)) ?? []

        // 通算データ
        var firstDescriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date)]
        )
        firstDescriptor.fetchLimit = 1
        firstWorkoutDate = (try? context.fetch(firstDescriptor))?.first?.date

        let allDescriptor = FetchDescriptor<WorkoutSession>()
        totalSessionCount = (try? context.fetch(allDescriptor))?.count ?? 0

        let profileDescriptor = FetchDescriptor<UserProfile>()
        userGoal = (try? context.fetch(profileDescriptor))?.first?.goals ?? ""
    }

    var totalVolume: Double {
        workoutSessions.reduce(0) { $0 + $1.totalVolume }
    }

    var exerciseCount: Int {
        let exerciseIds = workoutSessions.flatMap { $0.sets }.compactMap { $0.exercise?.id }
        return Set(exerciseIds).count
    }

    var totalCalories: Double {
        mealRecords.reduce(0) { $0 + $1.calories }
    }

    var totalProtein: Double {
        mealRecords.reduce(0) { $0 + $1.protein }
    }

    var totalFat: Double {
        mealRecords.reduce(0) { $0 + $1.fat }
    }

    var totalCarbs: Double {
        mealRecords.reduce(0) { $0 + $1.carbs }
    }

    var isToday: Bool {
        Calendar.current.isDateInToday(selectedDate)
    }

    var formattedDate: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: selectedDate)
    }
}
