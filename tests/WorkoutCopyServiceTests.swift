import XCTest
import SwiftData
@testable import BodyOps

final class WorkoutCopyServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var service: WorkoutCopyService!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: WorkoutSession.self, WorkoutSet.self, Exercise.self, configurations: config)
        context = ModelContext(container)
        service = WorkoutCopyService(context: context)
    }

    override func tearDown() {
        container = nil
        context = nil
        service = nil
        super.tearDown()
    }

    // TC-01: 前回セッションの全種目・セット・重量・回数をコピーできる
    func test_copyPreviousSession_copiesAllSetsCorrectly() throws {
        let exercise1 = Exercise(name: "ベンチプレス", category: "胸", isPreset: true)
        let exercise2 = Exercise(name: "スクワット", category: "脚", isPreset: true)
        context.insert(exercise1)
        context.insert(exercise2)

        let previousSession = WorkoutSession(date: Date().addingTimeInterval(-86400), memo: "")
        let set1 = WorkoutSet(setNumber: 1, weight: 80, reps: 5, exercise: exercise1, session: previousSession)
        let set2 = WorkoutSet(setNumber: 2, weight: 80, reps: 5, exercise: exercise1, session: previousSession)
        let set3 = WorkoutSet(setNumber: 1, weight: 100, reps: 8, exercise: exercise2, session: previousSession)
        context.insert(previousSession)
        [set1, set2, set3].forEach { context.insert($0) }
        try context.save()

        let copiedSets = try service.copyPreviousSession()

        XCTAssertNotNil(copiedSets)
        XCTAssertEqual(copiedSets?.count, 3)
        XCTAssertEqual(copiedSets?.filter { $0.exercise?.name == "ベンチプレス" }.count, 2)
        XCTAssertEqual(copiedSets?.filter { $0.exercise?.name == "スクワット" }.count, 1)
        XCTAssertEqual(copiedSets?.first { $0.exercise?.name == "スクワット" }?.weight, 100)
        XCTAssertEqual(copiedSets?.first { $0.exercise?.name == "スクワット" }?.reps, 8)
    }

    // TC-02: 前回セッションが存在しない場合はnilを返す
    func test_copyPreviousSession_withNoHistory_returnsNil() throws {
        let result = try service.copyPreviousSession()
        XCTAssertNil(result)
    }

    // TC-03: 直前のセットをコピーして次のセットを追加できる
    func test_copyLastSet_appendsSetWithSameWeightAndReps() {
        let exercise = Exercise(name: "ベンチプレス", category: "胸", isPreset: true)
        let existingSet = WorkoutSet(setNumber: 1, weight: 60, reps: 10, exercise: exercise, session: nil)

        let copied = service.copyLastSet(from: existingSet, newSetNumber: 2)

        XCTAssertEqual(copied.weight, 60)
        XCTAssertEqual(copied.reps, 10)
        XCTAssertEqual(copied.setNumber, 2)
        XCTAssertEqual(copied.exercise?.name, "ベンチプレス")
    }

    // TC-04: コピー後に重量を変更しても元データに影響しない
    func test_copyPreviousSession_isIndependentCopy() throws {
        let exercise = Exercise(name: "デッドリフト", category: "背中", isPreset: true)
        context.insert(exercise)

        let previousSession = WorkoutSession(date: Date().addingTimeInterval(-86400), memo: "")
        let originalSet = WorkoutSet(setNumber: 1, weight: 120, reps: 5, exercise: exercise, session: previousSession)
        context.insert(previousSession)
        context.insert(originalSet)
        try context.save()

        let copiedSets = try service.copyPreviousSession()
        copiedSets?.first?.weight = 130

        XCTAssertEqual(originalSet.weight, 120, "元のセットの重量が変更されていない")
    }

    // TC-05: volumeがコピー時に正しく計算される
    func test_copyLastSet_calculatesVolumeCorrectly() {
        let exercise = Exercise(name: "スクワット", category: "脚", isPreset: true)
        let existingSet = WorkoutSet(setNumber: 1, weight: 70, reps: 8, exercise: exercise, session: nil)

        let copied = service.copyLastSet(from: existingSet, newSetNumber: 2)

        XCTAssertEqual(copied.volume, 560, accuracy: 0.01)
    }
}
