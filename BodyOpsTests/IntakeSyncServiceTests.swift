import XCTest
import SwiftData
@testable import BodyOps

@MainActor
final class IntakeSyncServiceTests: XCTestCase {
    var container: ModelContainer!
    var context: ModelContext!
    var session: MockIntakeURLSession!
    var now: Date!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: IntakeSyncSetting.self, IntakeOutboxItem.self, MealRecord.self,
            WorkoutSession.self, WorkoutSet.self, Exercise.self,
            configurations: config
        )
        context = ModelContext(container)
        session = MockIntakeURLSession()
        now = ISO8601DateFormatter().date(from: "2026-09-12T00:00:00Z")!
        try? KeychainService.shared.deleteIntakeToken()
    }

    override func tearDown() {
        try? KeychainService.shared.deleteIntakeToken()
        container = nil
        context = nil
        session = nil
        now = nil
        super.tearDown()
    }

    func test_enqueueMeal_buildsReceiverPayloadFieldsWithoutImageData() throws {
        try configureSync()
        let meal = MealRecord(
            mealDescription: "鶏むね肉",
            mealType: "lunch",
            calories: 320,
            protein: 45,
            fat: 6,
            carbs: 12
        )
        meal.imageData = Data([1, 2, 3])
        meal.recordedAt = now
        context.insert(meal)
        try context.save()

        let item = try XCTUnwrap(try makeService().enqueue(meal: meal))
        let json = try jsonObject(from: item.payloadData)

        XCTAssertEqual(json["kind"] as? String, "meal")
        XCTAssertEqual(json["external_id"] as? String, "bodyops-meal-\(meal.id.uuidString)")
        XCTAssertNotNil(json["occurred_at"] as? String)
        XCTAssertEqual(json["title"] as? String, "鶏むね肉")
        XCTAssertEqual(json["calories_kcal"] as? Double, 320)
        XCTAssertEqual(json["protein_g"] as? Double, 45)
        XCTAssertEqual(json["fat_g"] as? Double, 6)
        XCTAssertEqual(json["carbs_g"] as? Double, 12)
        XCTAssertNil(json["protein"])
        XCTAssertNil(json["calories"])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["meal_id"] as? String, meal.id.uuidString)
        XCTAssertEqual(payload["meal_type"] as? String, "lunch")
        XCTAssertEqual(payload["description"] as? String, "鶏むね肉")
        XCTAssertNil(payload["imageData"])
        XCTAssertNil(payload["image_data"])
    }

    func test_enqueueWorkout_buildsReceiverPayloadFieldsWithDetailsNestedInPayload() throws {
        try configureSync()
        let bench = Exercise(name: "ベンチプレス", category: "胸", isPreset: true)
        let sessionRecord = WorkoutSession(date: now, memo: "重め")
        context.insert(bench)
        context.insert(sessionRecord)
        let first = WorkoutSet(setNumber: 1, weight: 60, reps: 10, exercise: bench, session: sessionRecord)
        let second = WorkoutSet(setNumber: 2, weight: 62.5, reps: 8, exercise: bench, session: sessionRecord)
        context.insert(first)
        context.insert(second)
        sessionRecord.totalVolume = first.volume + second.volume
        try context.save()

        let item = try XCTUnwrap(try makeService().enqueue(session: sessionRecord, sets: [first, second]))
        let json = try jsonObject(from: item.payloadData)

        XCTAssertEqual(json["kind"] as? String, "workout")
        XCTAssertEqual(json["external_id"] as? String, "bodyops-workout-\(sessionRecord.id.uuidString)")
        XCTAssertNotNil(json["occurred_at"] as? String)
        XCTAssertEqual(json["title"] as? String, "ベンチプレス")
        XCTAssertNotNil(json["duration_minutes"])
        let payload = try XCTUnwrap(json["payload"] as? [String: Any])
        XCTAssertEqual(payload["session_id"] as? String, sessionRecord.id.uuidString)
        XCTAssertEqual(payload["memo"] as? String, "重め")
        XCTAssertEqual(payload["total_volume"] as? Double, 1100)
        let exercises = try XCTUnwrap(payload["exercises"] as? [[String: Any]])
        XCTAssertEqual(exercises.count, 1)
        XCTAssertEqual(exercises[0]["exercise_name"] as? String, "ベンチプレス")
        let sets = try XCTUnwrap(exercises[0]["sets"] as? [[String: Any]])
        XCTAssertEqual(sets.map { $0["set_number"] as? Int }, [1, 2])
        XCTAssertNil(json["event_id"])
        XCTAssertNil(json["recorded_at"])
    }

    func test_enqueueSameMeal_updatesExistingOutboxItemWithoutDuplicate() throws {
        try configureSync()
        let meal = MealRecord(mealDescription: "プロテイン", mealType: "snack", calories: 120, protein: 24, fat: 1, carbs: 3)
        context.insert(meal)
        try context.save()
        let service = makeService()

        _ = try service.enqueue(meal: meal)
        meal.protein = 30
        _ = try service.enqueue(meal: meal)

        let items = try context.fetch(FetchDescriptor<IntakeOutboxItem>())
        XCTAssertEqual(items.count, 1)
        let json = try jsonObject(from: items[0].payloadData)
        XCTAssertEqual(json["protein_g"] as? Double, 30)
    }

    func test_flushPending_postsXIntakeTokenJSONAndDeletesOn2xxSuccess() async throws {
        try configureSync()
        let item = try enqueueMealForFlush()
        XCTAssertNotNil(item)
        session.statusCode = 204

        await makeService().flushPending()

        XCTAssertEqual(session.requests.count, 1)
        let request = session.requests[0]
        XCTAssertEqual(request.url?.absoluteString, IntakeSyncSetting.defaultEndpointURLString)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.value(forHTTPHeaderField: "X-Intake-Token"), "test-token")
        XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
        let items = try context.fetch(FetchDescriptor<IntakeOutboxItem>())
        XCTAssertTrue(items.isEmpty)
    }

    func test_flushPending_treatsInsertedFalseAsSuccessAndDeletes() async throws {
        try configureSync()
        _ = try enqueueMealForFlush()
        session.statusCode = 200
        session.responseData = "{\"ok\":true,\"kind\":\"meal\",\"inserted\":false}".data(using: .utf8)!

        await makeService().flushPending()

        let items = try context.fetch(FetchDescriptor<IntakeOutboxItem>())
        XCTAssertTrue(items.isEmpty)
    }

    func test_flushPending_keepsFailedItemAndSchedulesRetry() async throws {
        try configureSync()
        _ = try enqueueMealForFlush()
        session.statusCode = 500

        await makeService().flushPending()

        let items = try context.fetch(FetchDescriptor<IntakeOutboxItem>())
        XCTAssertEqual(items.count, 1)
        XCTAssertEqual(items[0].attemptCount, 1)
        XCTAssertNotNil(items[0].lastAttemptAt)
        XCTAssertGreaterThan(items[0].nextAttemptAt, now)
        XCTAssertEqual(session.requests.count, 1)
    }

    func test_mealSavePersistsLocalRecordWhenSyncIsNotConfigured() throws {
        let viewModel = MealRecordViewModel()
        viewModel.mealDescription = "納豆ごはん"
        viewModel.calories = 400

        viewModel.save(date: now, context: context)

        let meals = try context.fetch(FetchDescriptor<MealRecord>())
        XCTAssertEqual(meals.count, 1)
        XCTAssertEqual(meals[0].mealDescription, "納豆ごはん")
        let outbox = try context.fetch(FetchDescriptor<IntakeOutboxItem>())
        XCTAssertTrue(outbox.isEmpty)
    }

    private func configureSync() throws {
        context.insert(IntakeSyncSetting(enabled: true))
        try KeychainService.shared.saveIntakeToken("test-token")
        try context.save()
    }

    private func enqueueMealForFlush() throws -> IntakeOutboxItem? {
        let meal = MealRecord(mealDescription: "卵", mealType: "breakfast", calories: 80, protein: 7, fat: 5, carbs: 1)
        meal.recordedAt = now
        context.insert(meal)
        try context.save()
        return try makeService().enqueue(meal: meal)
    }

    private func makeService() -> IntakeSyncService {
        IntakeSyncService(context: context, session: session, now: { self.now })
    }

    private func jsonObject(from data: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }
}

final class MockIntakeURLSession: URLSessionProtocol, @unchecked Sendable {
    var statusCode = 200
    var responseData = Data()
    var requests: [URLRequest] = []

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        requests.append(request)
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}
