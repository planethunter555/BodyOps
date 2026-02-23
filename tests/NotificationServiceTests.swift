import XCTest
import UserNotifications
@testable import BodyOps

final class NotificationServiceTests: XCTestCase {

    var mockCenter: MockUNUserNotificationCenter!
    var service: NotificationService!

    override func setUp() {
        super.setUp()
        mockCenter = MockUNUserNotificationCenter()
        service = NotificationService(center: mockCenter)
    }

    // TC-01: 曜日・時刻を指定すると通知リクエストが登録される
    func test_schedule_registersOneRequestPerWeekday() async throws {
        let setting = NotificationSetting(isEnabled: true, weekdays: [2, 4, 6], hour: 20, minute: 0)
        try await service.schedule(setting: setting)

        XCTAssertEqual(mockCenter.addedRequests.count, 3)
    }

    // TC-02: isEnabled=false で全通知がキャンセルされる
    func test_cancelAll_removesAllPendingRequests() async throws {
        let setting = NotificationSetting(isEnabled: true, weekdays: [2, 4, 6], hour: 20, minute: 0)
        try await service.schedule(setting: setting)
        service.cancelAll()

        XCTAssertTrue(mockCenter.removedAllPending)
    }

    // TC-03: 再設定すると古い通知がキャンセルされ新しい設定で登録される
    func test_reschedule_cancelsPreviousAndAddsNew() async throws {
        let first = NotificationSetting(isEnabled: true, weekdays: [2, 4, 6], hour: 20, minute: 0)
        try await service.schedule(setting: first)

        mockCenter.addedRequests.removeAll()
        mockCenter.removedAllPending = false

        let second = NotificationSetting(isEnabled: true, weekdays: [2, 5], hour: 21, minute: 30)
        try await service.schedule(setting: second)

        XCTAssertTrue(mockCenter.removedAllPending, "前の通知がキャンセルされた")
        XCTAssertEqual(mockCenter.addedRequests.count, 2, "新しい設定で2件登録された")
    }

    // TC-04: 通知リクエストのIDが一意である
    func test_schedule_requestIDsAreUnique() async throws {
        let setting = NotificationSetting(isEnabled: true, weekdays: [2, 3, 4, 5, 6], hour: 7, minute: 0)
        try await service.schedule(setting: setting)

        let ids = mockCenter.addedRequests.map { $0.identifier }
        let uniqueIds = Set(ids)
        XCTAssertEqual(ids.count, uniqueIds.count, "全IDが一意である")
    }
}

// MARK: - Mock

final class MockUNUserNotificationCenter: UNUserNotificationCenterProtocol {
    var addedRequests: [UNNotificationRequest] = []
    var removedAllPending = false

    func add(_ request: UNNotificationRequest) async throws {
        addedRequests.append(request)
    }

    func removeAllPendingNotificationRequests() {
        removedAllPending = true
        addedRequests.removeAll()
    }

    func requestAuthorization(options: UNAuthorizationOptions) async throws -> Bool {
        return true
    }
}
