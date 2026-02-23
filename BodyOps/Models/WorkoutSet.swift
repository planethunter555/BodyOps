import Foundation
import SwiftData

@Model
final class WorkoutSet {
    var id: UUID
    var setNumber: Int
    var weight: Double
    var reps: Int
    var volume: Double
    var notes: String
    var createdAt: Date

    var session: WorkoutSession?
    var exercise: Exercise?

    init(setNumber: Int, weight: Double, reps: Int, exercise: Exercise? = nil, session: WorkoutSession? = nil) {
        self.id = UUID()
        self.setNumber = setNumber
        self.weight = weight
        self.reps = reps
        self.volume = weight * Double(reps)
        self.notes = ""
        self.createdAt = Date()
        self.exercise = exercise
        self.session = session
    }
}
