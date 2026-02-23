import Foundation
import SwiftData

@Model
final class Exercise {
    var id: UUID
    var name: String
    var category: String
    var isPreset: Bool
    var memo: String
    var createdAt: Date

    @Relationship(deleteRule: .nullify, inverse: \WorkoutSet.exercise)
    var sets: [WorkoutSet] = []

    init(name: String, category: String, isPreset: Bool = false, memo: String = "") {
        self.id = UUID()
        self.name = name
        self.category = category
        self.isPreset = isPreset
        self.memo = memo
        self.createdAt = Date()
    }
}
