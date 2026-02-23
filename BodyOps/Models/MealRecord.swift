import Foundation
import SwiftData

@Model
final class MealRecord {
    var id: UUID
    var mealDescription: String
    var imageData: Data?
    var calories: Double
    var protein: Double
    var fat: Double
    var carbs: Double
    var mealType: String
    var aiAnalysis: String
    var recordedAt: Date

    init(
        mealDescription: String = "",
        mealType: String = "lunch",
        calories: Double = 0,
        protein: Double = 0,
        fat: Double = 0,
        carbs: Double = 0
    ) {
        self.id = UUID()
        self.mealDescription = mealDescription
        self.mealType = mealType
        self.calories = calories
        self.protein = protein
        self.fat = fat
        self.carbs = carbs
        self.aiAnalysis = ""
        self.recordedAt = Date()
    }
}
