import Foundation
import SwiftData

@Model
final class NotificationSetting {
    var id: UUID
    var isEnabled: Bool
    var weekdays: [Int]
    var hour: Int
    var minute: Int

    init(isEnabled: Bool = false, weekdays: [Int] = [], hour: Int = 20, minute: Int = 0) {
        self.id = UUID()
        self.isEnabled = isEnabled
        self.weekdays = weekdays
        self.hour = hour
        self.minute = minute
    }
}
