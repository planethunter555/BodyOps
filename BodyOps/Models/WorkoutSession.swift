import Foundation
import SwiftData

@Model
final class WorkoutSession {
    var id: UUID
    var date: Date
    var memo: String
    var totalVolume: Double
    var createdAt: Date

    @Relationship(deleteRule: .cascade, inverse: \WorkoutSet.session)
    var sets: [WorkoutSet] = []

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.session)
    var chatMessages: [ChatMessage] = []

    init(date: Date = Date(), memo: String = "") {
        self.id = UUID()
        self.date = date
        self.memo = memo
        self.totalVolume = 0
        self.createdAt = Date()
    }
}
