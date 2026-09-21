import Foundation
import SwiftData

@Model
final class IntakeOutboxItem {
    var id: UUID
    var eventID: String
    var kind: String
    var payloadData: Data
    var createdAt: Date
    var nextAttemptAt: Date
    var lastAttemptAt: Date?
    var attemptCount: Int
    var lastError: String?

    init(
        eventID: String,
        kind: String,
        payloadData: Data,
        createdAt: Date = Date(),
        nextAttemptAt: Date = Date(),
        lastAttemptAt: Date? = nil,
        attemptCount: Int = 0,
        lastError: String? = nil
    ) {
        self.id = UUID()
        self.eventID = eventID
        self.kind = kind
        self.payloadData = payloadData
        self.createdAt = createdAt
        self.nextAttemptAt = nextAttemptAt
        self.lastAttemptAt = lastAttemptAt
        self.attemptCount = attemptCount
        self.lastError = lastError
    }
}
