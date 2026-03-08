import XCTest
import SwiftData
@testable import BodyOps

final class SystemPromptBuilderTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(
            for: WorkoutSession.self, WorkoutSet.self, Exercise.self,
                UserProfile.self, MealRecord.self, LLMSetting.self,
                NotificationSetting.self, ChatMessage.self,
            configurations: config
        )
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - buildWorkoutSection

    func testWorkoutSection_emptyDB_returnsEmpty() {
        let builder = SystemPromptBuilder(context: context)
        XCTAssertEqual(builder.buildWorkoutSection(), "")
    }

    func testWorkoutSection_withSession_containsExerciseAndWeight() throws {
        let exercise = Exercise(name: "スクワット", category: "脚", isPreset: true)
        context.insert(exercise)

        let session = WorkoutSession(date: Date(), memo: "")
        context.insert(session)

        let set1 = WorkoutSet(setNumber: 1, weight: 80, reps: 10, exercise: exercise, session: session)
        let set2 = WorkoutSet(setNumber: 2, weight: 80, reps: 8, exercise: exercise, session: session)
        context.insert(set1)
        context.insert(set2)
        session.totalVolume = 80 * 10 + 80 * 8

        try context.save()

        let builder = SystemPromptBuilder(context: context)
        let section = builder.buildWorkoutSection()

        XCTAssertFalse(section.isEmpty, "セッションがある場合セクションは空であってはならない")
        XCTAssertTrue(section.contains("スクワット"), "種目名がプロンプトに含まれること")
        XCTAssertTrue(section.contains("80.0kg×10回"), "重量と回数がプロンプトに含まれること")
        XCTAssertTrue(section.contains("80.0kg×8回"), "2セット目もプロンプトに含まれること")
        XCTAssertTrue(section.contains("1440"), "総ボリューム(1440)がプロンプトに含まれること")
    }

    func testWorkoutSection_sessionWithNoSets_isSkipped() throws {
        let session = WorkoutSession(date: Date(), memo: "")
        context.insert(session)
        session.totalVolume = 0
        try context.save()

        let builder = SystemPromptBuilder(context: context)
        let section = builder.buildWorkoutSection()

        // セットがないセッションだけの場合はヘッダーのみ or 空
        // "総ボリューム" は表示されないはず
        XCTAssertFalse(section.contains("総ボリューム"), "セットなしセッションは表示されない")
    }

    func testWorkoutSection_multipleExercises_allIncluded() throws {
        let ex1 = Exercise(name: "ベンチプレス", category: "胸", isPreset: true)
        let ex2 = Exercise(name: "デッドリフト", category: "背中", isPreset: true)
        context.insert(ex1)
        context.insert(ex2)

        let session = WorkoutSession(date: Date(), memo: "")
        context.insert(session)

        context.insert(WorkoutSet(setNumber: 1, weight: 60, reps: 10, exercise: ex1, session: session))
        context.insert(WorkoutSet(setNumber: 1, weight: 100, reps: 5, exercise: ex2, session: session))
        session.totalVolume = 60 * 10 + 100 * 5

        try context.save()

        let builder = SystemPromptBuilder(context: context)
        let section = builder.buildWorkoutSection()

        XCTAssertTrue(section.contains("ベンチプレス"))
        XCTAssertTrue(section.contains("デッドリフト"))
    }

    func testWorkoutSection_limitsTenSessions() throws {
        let exercise = Exercise(name: "スクワット", category: "脚", isPreset: true)
        context.insert(exercise)

        for i in 0..<12 {
            let date = Calendar.current.date(byAdding: .day, value: -i, to: Date())!
            let session = WorkoutSession(date: date, memo: "セッション\(i)")
            context.insert(session)
            let s = WorkoutSet(setNumber: 1, weight: Double(i) * 10 + 60, reps: 10, exercise: exercise, session: session)
            context.insert(s)
            session.totalVolume = s.weight * 10
        }
        try context.save()

        let builder = SystemPromptBuilder(context: context)
        let section = builder.buildWorkoutSection()

        // 12セッション中10セッションのみ（ヘッダーに"10セッション"と表示）
        XCTAssertTrue(section.contains("直近10セッション"), "10セッション上限が反映されること")
    }

    // MARK: - buildMealSection

    func testMealSection_emptyDB_returnsEmpty() {
        let builder = SystemPromptBuilder(context: context)
        XCTAssertEqual(builder.buildMealSection(), "")
    }

    func testMealSection_recentMeal_included() throws {
        let meal = MealRecord(
            mealDescription: "鶏むね肉",
            mealType: "lunch",
            calories: 300,
            protein: 40,
            fat: 5,
            carbs: 10
        )
        context.insert(meal)
        try context.save()

        let builder = SystemPromptBuilder(context: context)
        let section = builder.buildMealSection()

        XCTAssertFalse(section.isEmpty)
        XCTAssertTrue(section.contains("300"))
        XCTAssertTrue(section.contains("40"))
    }

    func testMealSection_oldMeal_excluded() throws {
        let meal = MealRecord(
            mealDescription: "古い食事",
            mealType: "dinner",
            calories: 500,
            protein: 30,
            fat: 20,
            carbs: 60
        )
        // recordedAt は Date() がデフォルトなので手動で5日前に変更
        let oldDate = Calendar.current.date(byAdding: .day, value: -5, to: Date())!
        meal.recordedAt = oldDate
        context.insert(meal)
        try context.save()

        let builder = SystemPromptBuilder(context: context)
        let section = builder.buildMealSection()

        XCTAssertEqual(section, "", "2日以上前の食事は含まれないこと")
    }

    // MARK: - loadSets fallback

    func testLoadSets_fallbackFetch_whenSessionSetsEmpty() throws {
        // session.sets が空に見えるケースのフォールバックをテスト
        let exercise = Exercise(name: "ランジ", category: "脚", isPreset: true)
        context.insert(exercise)

        let session = WorkoutSession(date: Date(), memo: "")
        context.insert(session)
        let set = WorkoutSet(setNumber: 1, weight: 50, reps: 12, exercise: exercise, session: session)
        context.insert(set)
        session.totalVolume = 600
        try context.save()

        let builder = SystemPromptBuilder(context: context)
        // loadSets は session.sets または直接フェッチで結果を返すはず
        let sets = builder.loadSets(for: session)
        XCTAssertFalse(sets.isEmpty, "フォールバックを含めてセットを取得できること")
        XCTAssertEqual(sets.first?.weight, 50)
    }

    // MARK: - Full Prompt

    func testBuildFullPrompt_containsAllSections() throws {
        // プロファイル
        let profile = UserProfile()
        profile.goals = "筋肥大"
        context.insert(profile)

        // セッション
        let exercise = Exercise(name: "ベンチプレス", category: "胸", isPreset: true)
        context.insert(exercise)
        let session = WorkoutSession(date: Date(), memo: "")
        context.insert(session)
        let s = WorkoutSet(setNumber: 1, weight: 60, reps: 10, exercise: exercise, session: session)
        context.insert(s)
        session.totalVolume = 600

        // 食事
        let meal = MealRecord(mealDescription: "プロテイン", mealType: "snack", calories: 200, protein: 30, fat: 3, carbs: 10)
        context.insert(meal)

        try context.save()

        let builder = SystemPromptBuilder(context: context)
        let prompt = builder.build()

        XCTAssertTrue(prompt.contains("Body Ops"), "ベースプロンプトが含まれること")
        XCTAssertTrue(prompt.contains("筋肥大"), "目標が含まれること")
        XCTAssertTrue(prompt.contains("ベンチプレス"), "トレーニングデータが含まれること")
        XCTAssertTrue(prompt.contains("200"), "食事データが含まれること")
        XCTAssertTrue(prompt.contains("ルール"), "ルールセクションが含まれること")
    }
}
