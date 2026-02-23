import Foundation
import SwiftData

@Model
final class ChatMessage {
    var id: UUID
    var role: String
    var content: String
    var imageData: Data?
    var chatType: String
    var sessionTag: String
    var createdAt: Date

    var session: WorkoutSession?

    init(role: String, content: String, chatType: String = "workout_advice", sessionTag: String = "") {
        self.id = UUID()
        self.role = role
        self.content = content
        self.chatType = chatType
        self.sessionTag = sessionTag
        self.createdAt = Date()
    }
}
