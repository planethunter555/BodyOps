import XCTest
import SwiftData
@testable import BodyOps

final class ExercisePresetServiceTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!
    var service: ExercisePresetService!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: Exercise.self, configurations: config)
        context = ModelContext(container)
        service = ExercisePresetService(context: context)
    }

    override func tearDown() {
        container = nil
        context = nil
        service = nil
        super.tearDown()
    }

    // TC-01: 初回実行でExercisePresets.jsonの全種目が投入される
    func test_seedIfNeeded_insertsAllPresets() throws {
        try service.seedIfNeeded()

        let count = try context.fetchCount(FetchDescriptor<Exercise>())
        XCTAssertEqual(count, presetCountInBundle())
    }

    // TC-02: 2回呼んでも重複しない
    func test_seedIfNeeded_isIdempotent() throws {
        try service.seedIfNeeded()
        let firstCount = try context.fetchCount(FetchDescriptor<Exercise>())

        try service.seedIfNeeded()
        let secondCount = try context.fetchCount(FetchDescriptor<Exercise>())

        XCTAssertEqual(secondCount, firstCount, "2回実行しても件数が増えない")
    }

    private func presetCountInBundle() -> Int {
        guard let url = Bundle.main.url(forResource: "ExercisePresets", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let entries = try? JSONDecoder().decode([ExercisePresetEntry].self, from: data) else {
            XCTFail("ExercisePresets.jsonが読み込めない")
            return -1
        }
        return entries.count
    }

    // TC-03: 全種目がisPreset = true
    func test_seedIfNeeded_allExercisesArePreset() throws {
        try service.seedIfNeeded()

        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { !$0.isPreset })
        let nonPreset = try context.fetch(descriptor)
        XCTAssertTrue(nonPreset.isEmpty, "プリセット以外の種目が存在しない")
    }

    // TC-04: 6カテゴリが全て存在する
    func test_seedIfNeeded_containsAllCategories() throws {
        try service.seedIfNeeded()

        let categories = ["胸", "背中", "脚", "肩", "腕", "腹"]
        for category in categories {
            let descriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.category == category }
            )
            let exercises = try context.fetch(descriptor)
            XCTAssertGreaterThan(exercises.count, 0, "\(category)カテゴリが存在する")
        }
    }

    // TC-05: 主要種目が含まれている
    func test_seedIfNeeded_containsKeyExercises() throws {
        try service.seedIfNeeded()

        let keyExercises = ["ベンチプレス", "スクワット", "デッドリフト"]
        for name in keyExercises {
            let descriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.name == name }
            )
            let found = try context.fetch(descriptor)
            XCTAssertFalse(found.isEmpty, "\(name)が存在する")
        }
    }
}
