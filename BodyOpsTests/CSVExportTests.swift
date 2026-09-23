import XCTest
import SwiftData
@testable import BodyOps

final class ModelContainerConfigurationTests: XCTestCase {

    func test_appSchema_withCloudKitDisabled_createsInMemoryContainer() throws {
        let schema = Schema([
            UserProfile.self,
            Exercise.self,
            WorkoutSession.self,
            WorkoutSet.self,
            ChatMessage.self,
            MealRecord.self,
            NotificationSetting.self,
            LLMSetting.self,
            APIUsageRecord.self
        ])
        let configuration = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true,
            cloudKitDatabase: .none
        )

        XCTAssertNoThrow(
            try ModelContainer(for: schema, configurations: configuration)
        )
    }

    func test_modelContainerDiagnostics_format_includesNestedNSErrorDetails() {
        let deepest = NSError(
            domain: "BodyOps.DeepError",
            code: 300,
            userInfo: ["deep-key": "deep-value"]
        )
        let underlying = NSError(
            domain: "BodyOps.UnderlyingError",
            code: 200,
            userInfo: [
                "underlying-key": "underlying-value",
                NSUnderlyingErrorKey: deepest
            ]
        )
        let error = NSError(
            domain: "BodyOps.TopError",
            code: 100,
            userInfo: [
                "top-key": "top-value",
                NSUnderlyingErrorKey: underlying
            ]
        )

        let formatted = ModelContainerDiagnostics.format(error: error)

        XCTAssertTrue(formatted.contains("BodyOps.TopError"))
        XCTAssertTrue(formatted.contains("code: 100"))
        XCTAssertTrue(formatted.contains("top-key"))
        XCTAssertTrue(formatted.contains("top-value"))
        XCTAssertTrue(formatted.contains("BodyOps.UnderlyingError"))
        XCTAssertTrue(formatted.contains("code: 200"))
        XCTAssertTrue(formatted.contains("underlying-key"))
        XCTAssertTrue(formatted.contains("underlying-value"))
        XCTAssertTrue(formatted.contains("BodyOps.DeepError"))
        XCTAssertTrue(formatted.contains("code: 300"))
        XCTAssertTrue(formatted.contains("deep-key"))
        XCTAssertTrue(formatted.contains("deep-value"))
    }
}

final class CSVExportGeneratorTests: XCTestCase {

    // MARK: - Workouts

    func test_workoutsCSV_emptyArray_producesHeaderOnly() {
        let csv = CSVExportGenerator.workoutsCSV(rows: [])
        XCTAssertEqual(csv, CSVExportGenerator.workoutsHeader + "\r\n")
    }

    func test_workoutsCSV_header_matchesRequiredColumns() {
        XCTAssertEqual(
            CSVExportGenerator.workoutsHeader,
            "session_id,session_date,exercise_name,category,set_number,weight_kg,reps,volume,memo"
        )
    }

    func test_workoutsCSV_oneRowPerSet() {
        let sessionId = UUID()
        let date = makeDate(year: 2026, month: 3, day: 5, hour: 7, minute: 30, second: 15)
        let rows = [
            WorkoutSetCSVRow(
                sessionId: sessionId, sessionDate: date, exerciseName: "ベンチプレス", category: "胸",
                setNumber: 1, weightKg: 60, reps: 8, volume: 480, memo: ""
            ),
            WorkoutSetCSVRow(
                sessionId: sessionId, sessionDate: date, exerciseName: "ベンチプレス", category: "胸",
                setNumber: 2, weightKg: 62.5, reps: 7, volume: 437.5, memo: ""
            )
        ]
        let csv = CSVExportGenerator.workoutsCSV(rows: rows)
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 3) // header + 2 rows
        XCTAssertEqual(lines[0], CSVExportGenerator.workoutsHeader)
        XCTAssertEqual(lines[1], "\(sessionId.uuidString),2026-03-05 07:30:15,ベンチプレス,胸,1,60.0,8,480.0,")
        XCTAssertEqual(lines[2], "\(sessionId.uuidString),2026-03-05 07:30:15,ベンチプレス,胸,2,62.5,7,437.5,")
    }

    func test_workoutsCSV_acceptsWorkoutSessions() {
        let exercise = Exercise(name: "デッドリフト", category: "背中")
        let session = WorkoutSession(
            date: makeDate(year: 2026, month: 4, day: 1, hour: 20, minute: 0, second: 0),
            memo: "重い"
        )
        let set = WorkoutSet(setNumber: 1, weight: 100, reps: 5, exercise: exercise, session: session)
        session.sets = [set]

        let csv = CSVExportGenerator.workoutsCSV(sessions: [session])

        XCTAssertTrue(csv.contains(",2026-04-01 20:00:00,デッドリフト,背中,1,100.0,5,500.0,重い"))
    }

    func test_workoutsCSV_dateFormat_isPOSIXGregorianYYYYMMddHHmmss() {
        let date = makeDate(year: 2026, month: 12, day: 31, hour: 23, minute: 59, second: 1)
        let row = WorkoutSetCSVRow(
            sessionId: UUID(), sessionDate: date, exerciseName: "x", category: "y",
            setNumber: 1, weightKg: 1, reps: 1, volume: 1, memo: ""
        )
        let csv = CSVExportGenerator.workoutsCSV(rows: [row])
        XCTAssertTrue(csv.contains("2026-12-31 23:59:01"), "date should be formatted as yyyy-MM-dd HH:mm:ss: \(csv)")
    }

    func test_workoutsCSV_memoWithComma_isRFC4180Escaped() {
        let row = WorkoutSetCSVRow(
            sessionId: UUID(), sessionDate: Date(), exerciseName: "スクワット", category: "脚",
            setNumber: 1, weightKg: 80, reps: 5, volume: 400, memo: "調子良い, 次は90kg狙う"
        )
        let csv = CSVExportGenerator.workoutsCSV(rows: [row])
        XCTAssertTrue(csv.contains("\"調子良い, 次は90kg狙う\""), "memo containing a comma must be quoted: \(csv)")
    }

    func test_workoutsCSV_memoWithQuotesAndNewline_isRFC4180Escaped() {
        let row = WorkoutSetCSVRow(
            sessionId: UUID(), sessionDate: Date(), exerciseName: "スクワット", category: "脚",
            setNumber: 1, weightKg: 80, reps: 5, volume: 400, memo: "\"最高\"の出来\n次も頑張る"
        )
        let csv = CSVExportGenerator.workoutsCSV(rows: [row])
        XCTAssertTrue(
            csv.contains("\"\"\"最高\"\"の出来\n次も頑張る\""),
            "quotes must be doubled and the whole field wrapped in quotes: \(csv)"
        )
    }

    // MARK: - Meals

    func test_mealsCSV_emptyArray_producesHeaderOnly() {
        let csv = CSVExportGenerator.mealsCSV(rows: [])
        XCTAssertEqual(csv, CSVExportGenerator.mealsHeader + "\r\n")
    }

    func test_mealsCSV_header_matchesRequiredColumns_noImageOrDuration() {
        let header = CSVExportGenerator.mealsHeader
        XCTAssertEqual(header, "meal_id,recorded_at,meal_type,description,calories_kcal,protein_g,fat_g,carbs_g")
        XCTAssertFalse(header.contains("image"))
        XCTAssertFalse(header.contains("duration"))
    }

    func test_mealsCSV_oneRowPerRecord() {
        let mealId = UUID()
        let date = makeDate(year: 2026, month: 1, day: 2, hour: 8, minute: 5, second: 0)
        let row = MealRecordCSVRow(
            mealId: mealId, recordedAt: date, mealType: "breakfast", mealDescription: "オートミール",
            calories: 420, protein: 24, fat: 12, carbs: 55
        )
        let csv = CSVExportGenerator.mealsCSV(rows: [row])
        let lines = csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }

        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(
            lines[1],
            "\(mealId.uuidString),2026-01-02 08:05:00,breakfast,オートミール,420.0,24.0,12.0,55.0"
        )
    }

    func test_mealsCSV_acceptsMealRecordsAndDoesNotIncludeImageData() {
        let record = MealRecord(
            mealDescription: "プロテイン",
            mealType: "snack",
            calories: 120,
            protein: 24,
            fat: 1,
            carbs: 3
        )
        record.recordedAt = makeDate(year: 2026, month: 2, day: 3, hour: 10, minute: 0, second: 0)
        record.imageData = Data("raw-image-bytes".utf8)

        let csv = CSVExportGenerator.mealsCSV(records: [record])

        XCTAssertTrue(csv.contains(",2026-02-03 10:00:00,snack,プロテイン,120.0,24.0,1.0,3.0"))
        XCTAssertFalse(csv.contains("raw-image-bytes"))
        XCTAssertFalse(csv.contains("image"))
    }

    func test_mealsCSV_descriptionWithCommaAndQuote_isRFC4180Escaped() {
        let row = MealRecordCSVRow(
            mealId: UUID(), recordedAt: Date(), mealType: "lunch",
            mealDescription: "鶏胸肉200g, 玄米, \"大盛り\"",
            calories: 600, protein: 40, fat: 10, carbs: 70
        )
        let csv = CSVExportGenerator.mealsCSV(rows: [row])
        XCTAssertTrue(
            csv.contains("\"鶏胸肉200g, 玄米, \"\"大盛り\"\"\""),
            "description containing commas and quotes must be RFC4180 escaped: \(csv)"
        )
    }

    // MARK: - Helpers

    private func makeDate(year: Int, month: Int, day: Int, hour: Int, minute: Int, second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone.current
        let components = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        return calendar.date(from: components)!
    }
}

final class ICloudCSVWriterTests: XCTestCase {

    /// iCloud未設定/未サインインの環境（CI・テスト実行環境）では
    /// url(forUbiquityContainerIdentifier:) が nil を返す。
    /// ネットワークアクセスやクラッシュを伴わず、即座に `.unavailable` を返すことを確認する。
    func test_write_withUnavailableICloudContainer_returnsUnavailableWithoutBlocking() {
        let start = Date()
        let outcome = ICloudCSVWriter.write(
            workoutRows: [],
            mealRows: [],
            containerIdentifier: ICloudExportService.containerIdentifier,
            containerURLProvider: { _ in nil }
        )
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertEqual(outcome, .unavailable)
        XCTAssertLessThan(elapsed, 2.0, "should fail fast without network access when iCloud is unavailable")
    }

    func test_write_isPureAndDeterministic_forSameUnavailableContainer() {
        let outcome1 = ICloudCSVWriter.write(
            workoutRows: [], mealRows: [], containerIdentifier: "iCloud.com.bodyops.app", containerURLProvider: { _ in nil }
        )
        let outcome2 = ICloudCSVWriter.write(
            workoutRows: [], mealRows: [], containerIdentifier: "iCloud.com.bodyops.app", containerURLProvider: { _ in nil }
        )
        XCTAssertEqual(outcome1, outcome2)
    }

    /// CSV は Finder / 「ファイル」アプリから見える Documents サブディレクトリ配下に書かれる。
    func test_write_writesBothCSVFilesIntoDocumentsSubdirectory() throws {
        let container = makeTemporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let outcome = ICloudCSVWriter.write(
            workoutRows: [],
            mealRows: [],
            containerIdentifier: ICloudExportService.containerIdentifier,
            containerURLProvider: { _ in container }
        )

        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(
            try String(contentsOf: documents.appendingPathComponent("bodyops_workouts.csv"), encoding: .utf8),
            CSVExportGenerator.workoutsHeader + "\r\n"
        )
        XCTAssertEqual(
            try String(contentsOf: documents.appendingPathComponent("bodyops_meals.csv"), encoding: .utf8),
            CSVExportGenerator.mealsHeader + "\r\n"
        )
    }

    /// 回帰防止: コンテナ直下には CSV を作らない（直下だと Finder / 「ファイル」アプリに出ない）。
    func test_write_doesNotWriteCSVFilesAtContainerRoot() throws {
        let container = makeTemporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let outcome = ICloudCSVWriter.write(
            workoutRows: [],
            mealRows: [],
            containerIdentifier: ICloudExportService.containerIdentifier,
            containerURLProvider: { _ in container }
        )

        XCTAssertEqual(outcome, .success)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: container.appendingPathComponent("bodyops_workouts.csv").path)
        )
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: container.appendingPathComponent("bodyops_meals.csv").path)
        )
    }

    /// 既存の Documents ディレクトリとその中の無関係なファイルを消さない。
    func test_write_preservesExistingDocumentsDirectoryContents() throws {
        let container = makeTemporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        try FileManager.default.createDirectory(at: documents, withIntermediateDirectories: true)
        let unrelated = documents.appendingPathComponent("unrelated.txt")
        try "keep-me".write(to: unrelated, atomically: true, encoding: .utf8)

        let outcome = ICloudCSVWriter.write(
            workoutRows: [],
            mealRows: [],
            containerIdentifier: ICloudExportService.containerIdentifier,
            containerURLProvider: { _ in container }
        )

        XCTAssertEqual(outcome, .success)
        XCTAssertEqual(try String(contentsOf: unrelated, encoding: .utf8), "keep-me")
        XCTAssertTrue(
            FileManager.default.fileExists(atPath: documents.appendingPathComponent("bodyops_workouts.csv").path)
        )
    }

    private func makeTemporaryContainer() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}

@MainActor
final class ICloudExportServiceTests: XCTestCase {

    /// 手動書き出し（debounceなし）はローカル環境で即座に完了し、ハングしない。
    /// iCloudの実可否は実行環境に依存するため、ここでは完了性だけを検証する。
    func test_exportNow_completesWithoutHanging() async {
        let service = ICloudExportService.shared
        let wasEnabled = service.isEnabled
        defer { service.isEnabled = wasEnabled }
        service.isEnabled = true

        let expectation = XCTestExpectation(description: "exportNow completes")
        Task {
            await service.exportNow(context: makeInMemoryContext())
            expectation.fulfill()
        }
        await fulfillment(of: [expectation], timeout: 5.0)
    }

    func test_scheduleExport_whenDisabled_doesNothingSynchronously() {
        let service = ICloudExportService.shared
        service.isEnabled = false
        let statusBefore = service.status

        service.scheduleExport(context: makeInMemoryContext())

        XCTAssertEqual(service.status, statusBefore)
    }

    private func makeInMemoryContext() -> ModelContext {
        let schema = Schema([
            UserProfile.self, Exercise.self, WorkoutSession.self, WorkoutSet.self,
            ChatMessage.self, MealRecord.self, NotificationSetting.self, LLMSetting.self, APIUsageRecord.self
        ])
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        let container = try! ModelContainer(for: schema, configurations: [config])
        return ModelContext(container)
    }
}
