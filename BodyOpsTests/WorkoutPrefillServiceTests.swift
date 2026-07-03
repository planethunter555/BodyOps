import XCTest
import SwiftData
@testable import BodyOps

final class WorkoutPrefillServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var service: WorkoutPrefillService!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: Exercise.self, WorkoutSession.self, WorkoutSet.self,
            configurations: config
        )
        context = ModelContext(container)
        service = WorkoutPrefillService(context: context)
    }

    override func tearDown() {
        container = nil
        context = nil
        service = nil
        super.tearDown()
    }

    // MARK: - Helpers

    @discardableResult
    private func makeSession(daysAgo: Int, exercise: Exercise,
                             sets: [(weight: Double, reps: Int)]) -> WorkoutSession {
        let date = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        let session = WorkoutSession(date: date)
        context.insert(session)
        for (index, set) in sets.enumerated() {
            let workoutSet = WorkoutSet(
                setNumber: index + 1,
                weight: set.weight,
                reps: set.reps,
                exercise: exercise,
                session: session
            )
            // createdAt順の判定が日付順と一致するようにセッション日付に合わせる
            workoutSet.createdAt = date
            context.insert(workoutSet)
        }
        try! context.save()
        return session
    }

    private func makeExercise(_ name: String) -> Exercise {
        let exercise = Exercise(name: name, category: "胸", isPreset: true)
        context.insert(exercise)
        return exercise
    }

    // MARK: - latestEntries

    func test_latestEntries_returnsSetsOfMostRecentSession() {
        let bench = makeExercise("ベンチプレス")
        makeSession(daysAgo: 7, exercise: bench, sets: [(60, 10), (60, 8)])
        makeSession(daysAgo: 2, exercise: bench, sets: [(65, 10), (65, 8), (65, 6)])

        let entries = service.latestEntries(for: bench)

        XCTAssertEqual(entries.count, 3)
        XCTAssertEqual(entries.map(\.weight), [65, 65, 65])
        XCTAssertEqual(entries.map(\.setNumber), [1, 2, 3])
    }

    func test_latestEntries_withNoHistory_returnsEmpty() {
        let squat = makeExercise("スクワット")

        XCTAssertTrue(service.latestEntries(for: squat).isEmpty)
    }

    // MARK: - entries(for date:)

    func test_entriesForDate_groupsByExercisePreservingOrder() {
        let bench = makeExercise("ベンチプレス")
        let squat = makeExercise("スクワット")
        let date = Calendar.current.date(byAdding: .day, value: -3, to: Date())!
        let session = WorkoutSession(date: date)
        context.insert(session)
        // ベンチ2セット → スクワット1セットの順に記録
        context.insert(WorkoutSet(setNumber: 1, weight: 60, reps: 10, exercise: bench, session: session))
        context.insert(WorkoutSet(setNumber: 2, weight: 60, reps: 8, exercise: bench, session: session))
        context.insert(WorkoutSet(setNumber: 1, weight: 100, reps: 5, exercise: squat, session: session))
        try! context.save()

        let entries = service.entries(for: date)

        XCTAssertEqual(entries.count, 2)
        XCTAssertEqual(entries[0].exercise.name, "ベンチプレス")
        XCTAssertEqual(entries[0].sets.count, 2)
        XCTAssertEqual(entries[1].exercise.name, "スクワット")
        XCTAssertEqual(entries[1].sets.map(\.weight), [100])
    }

    func test_entriesForDate_mergesMultipleSessionsOnSameDay() {
        let bench = makeExercise("ベンチプレス")
        let squat = makeExercise("スクワット")
        makeSession(daysAgo: 1, exercise: bench, sets: [(60, 10)])
        makeSession(daysAgo: 1, exercise: squat, sets: [(100, 5)])

        let date = Calendar.current.date(byAdding: .day, value: -1, to: Date())!
        let entries = service.entries(for: date)

        XCTAssertEqual(entries.count, 2)
    }

    func test_entriesForDate_withNoSessions_returnsEmpty() {
        XCTAssertTrue(service.entries(for: Date()).isEmpty)
    }

    // MARK: - mostRecentSessionDate

    func test_mostRecentSessionDate_returnsLatestBeforeGivenDate() {
        let bench = makeExercise("ベンチプレス")
        makeSession(daysAgo: 10, exercise: bench, sets: [(60, 10)])
        let recent = makeSession(daysAgo: 2, exercise: bench, sets: [(65, 10)])

        let result = service.mostRecentSessionDate(before: Date())

        XCTAssertNotNil(result)
        XCTAssertTrue(Calendar.current.isDate(result!, inSameDayAs: recent.date))
    }

    func test_mostRecentSessionDate_excludesSameDay() {
        let bench = makeExercise("ベンチプレス")
        makeSession(daysAgo: 0, exercise: bench, sets: [(60, 10)])
        makeSession(daysAgo: 5, exercise: bench, sets: [(55, 10)])

        let result = service.mostRecentSessionDate(before: Date())

        // 当日のセッションは除外され、5日前が返る
        let expected = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        XCTAssertNotNil(result)
        XCTAssertTrue(Calendar.current.isDate(result!, inSameDayAs: expected))
    }

    func test_mostRecentSessionDate_withNoHistory_returnsNil() {
        XCTAssertNil(service.mostRecentSessionDate(before: Date()))
    }
}
