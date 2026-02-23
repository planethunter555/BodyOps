import Foundation
import UserNotifications

protocol UNUserNotificationCenterProtocol {
    func add(_ request: UNNotificationRequest) async throws
    func removeAllPendingNotificationRequests()
    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool
}

extension UNUserNotificationCenter: UNUserNotificationCenterProtocol {}

final class NotificationService {
    private let center: UNUserNotificationCenterProtocol

    init(center: UNUserNotificationCenterProtocol = UNUserNotificationCenter.current()) {
        self.center = center
    }

    func requestAuthorization() async throws -> Bool {
        try await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    func schedule(setting: NotificationSetting) async throws {
        center.removeAllPendingNotificationRequests()
        guard setting.isEnabled else { return }

        for weekday in setting.weekdays {
            let content = UNMutableNotificationContent()
            content.title = "トレーニングリマインダー"
            content.body = "今日もトレーニングを頑張りましょう！"
            content.sound = .default

            var dateComponents = DateComponents()
            dateComponents.weekday = weekday
            dateComponents.hour = setting.hour
            dateComponents.minute = setting.minute

            let trigger = UNCalendarNotificationTrigger(dateMatching: dateComponents, repeats: true)
            let identifier = "bodyops.workout.reminder.weekday.\(weekday)"
            let request = UNNotificationRequest(identifier: identifier, content: content, trigger: trigger)
            try await center.add(request)
        }
    }

    func cancelAll() {
        center.removeAllPendingNotificationRequests()
    }
}
