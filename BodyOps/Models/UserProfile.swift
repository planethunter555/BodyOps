import Foundation
import SwiftData

@Model
final class UserProfile {
    var id: UUID
    var height: Double
    var weight: Double
    var bodyFatPercentage: Double
    var targetMuscleMass: Double
    var targetBodyFat: Double
    var weeklyWorkoutDays: Int
    var goals: String
    var constraints: String
    var systemPromptPrefix: String
    var createdAt: Date

    init(
        height: Double = 170,
        weight: Double = 70,
        bodyFatPercentage: Double = 20,
        targetMuscleMass: Double = 60,
        targetBodyFat: Double = 15,
        weeklyWorkoutDays: Int = 3,
        goals: String = "",
        constraints: String = "",
        systemPromptPrefix: String = ""
    ) {
        self.id = UUID()
        self.height = height
        self.weight = weight
        self.bodyFatPercentage = bodyFatPercentage
        self.targetMuscleMass = targetMuscleMass
        self.targetBodyFat = targetBodyFat
        self.weeklyWorkoutDays = weeklyWorkoutDays
        self.goals = goals
        self.constraints = constraints
        self.systemPromptPrefix = systemPromptPrefix
        self.createdAt = Date()
    }
}
