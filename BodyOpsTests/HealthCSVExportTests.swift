import XCTest
@testable import BodyOps

/// Apple ヘルスケア（HealthKit）由来データのCSV生成テスト。
/// HealthKit 本体は実機/シミュレータでないと動かないため、
/// 「HealthKitから取った結果の構造体 → CSV文字列」の純粋な変換だけを検証する。
final class HealthCSVExportGeneratorTests: XCTestCase {

    // MARK: - ヘッダ / 0件

    func test_headers_matchRequiredColumns() {
        XCTAssertEqual(HealthCSVExportGenerator.sleepHeader, "start,end,stage,source")
        XCTAssertEqual(HealthCSVExportGenerator.dailyHeader, "date,metric,value,unit,source")
        XCTAssertEqual(HealthCSVExportGenerator.bodyHeader, "recorded_at,metric,value,unit,source")
    }

    /// 0件でもヘッダ行だけのCSVを返す（取り込み側が「ファイルが無い」と「0件」を区別できるように）。
    func test_emptyRows_produceHeaderOnlyNotEmptyString() {
        XCTAssertEqual(
            HealthCSVExportGenerator.sleepCSV(rows: []),
            HealthCSVExportGenerator.sleepHeader + "\r\n"
        )
        XCTAssertEqual(
            HealthCSVExportGenerator.dailyCSV(rows: []),
            HealthCSVExportGenerator.dailyHeader + "\r\n"
        )
        XCTAssertEqual(
            HealthCSVExportGenerator.bodyCSV(rows: []),
            HealthCSVExportGenerator.bodyHeader + "\r\n"
        )
    }

    func test_allCSVs_useCRLFLineEndings() {
        let csv = HealthCSVExportGenerator.dailyCSV(
            rows: [makeDailyRow(metric: .steps, value: 1000)],
            timeZone: tokyo
        )
        XCTAssertTrue(csv.hasSuffix("\r\n"))
        XCTAssertEqual(csv.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 2)
        // 単独の LF は含まない（全ての行末が CRLF であること）
        XCTAssertFalse(csv.replacingOccurrences(of: "\r\n", with: "").contains("\n"))
    }

    // MARK: - 睡眠

    /// 睡眠6ステージすべてが仕様どおりの文字列になる。
    func test_sleepCSV_allSixStages_mapToSpecifiedStrings() {
        let expected: [(HealthSleepStage, String)] = [
            (.inBed, "in_bed"),
            (.asleepUnspecified, "asleep_unspecified"),
            (.asleepCore, "asleep_core"),
            (.asleepDeep, "asleep_deep"),
            (.asleepREM, "asleep_rem"),
            (.awake, "awake")
        ]
        // 網羅性チェック: ケースを足したらこのテストが落ちるようにする
        XCTAssertEqual(HealthSleepStage.allCases.count, expected.count)

        let start = makeDate(2026, 10, 12, 23, 10, 0)
        let rows = expected.map { stage, _ in
            HealthSleepCSVRow(start: start, end: start.addingTimeInterval(1800), stage: stage, source: "Garmin")
        }
        let lines = csvLines(HealthCSVExportGenerator.sleepCSV(rows: rows, timeZone: tokyo))

        XCTAssertEqual(lines.count, expected.count + 1)
        for (index, pair) in expected.enumerated() {
            XCTAssertEqual(pair.0.csvValue, pair.1)
            XCTAssertEqual(
                lines[index + 1],
                "2026-10-12T23:10:00+09:00,2026-10-12T23:40:00+09:00,\(pair.1),Garmin"
            )
        }
    }

    /// 睡眠は日ごとに合算せず、区間のまま1行ずつ出す。
    func test_sleepCSV_keepsEachIntervalWithoutDailyAggregation() {
        let base = makeDate(2026, 10, 12, 23, 0, 0)
        let rows = [
            HealthSleepCSVRow(start: base, end: base.addingTimeInterval(600), stage: .inBed, source: "Garmin"),
            HealthSleepCSVRow(
                start: base.addingTimeInterval(600),
                end: base.addingTimeInterval(3600),
                stage: .asleepCore,
                source: "Garmin"
            ),
            HealthSleepCSVRow(
                start: base.addingTimeInterval(3600),
                end: base.addingTimeInterval(5400),
                stage: .asleepDeep,
                source: "Garmin"
            )
        ]
        let lines = csvLines(HealthCSVExportGenerator.sleepCSV(rows: rows, timeZone: tokyo))
        XCTAssertEqual(lines.count, 4, "3区間は合算されず3行で出るべき")
        XCTAssertTrue(lines[1].contains("in_bed"))
        XCTAssertTrue(lines[2].contains("asleep_core"))
        XCTAssertTrue(lines[3].contains("asleep_deep"))
    }

    // MARK: - ISO8601（タイムゾーンオフセット付き）

    func test_sleepCSV_timestamps_areISO8601WithTimezoneOffset() {
        let row = HealthSleepCSVRow(
            start: makeDate(2026, 10, 12, 23, 10, 0),
            end: makeDate(2026, 10, 13, 6, 45, 30),
            stage: .asleepREM,
            source: "Garmin"
        )
        let lines = csvLines(HealthCSVExportGenerator.sleepCSV(rows: [row], timeZone: tokyo))
        XCTAssertEqual(lines[1], "2026-10-12T23:10:00+09:00,2026-10-13T06:45:30+09:00,asleep_rem,Garmin")
    }

    func test_bodyCSV_recordedAt_isISO8601WithTimezoneOffset() {
        let row = HealthBodyCSVRow(
            recordedAt: makeDate(2026, 10, 12, 7, 5, 0),
            metric: .weightKg,
            value: 72.4,
            source: "eufy Life"
        )
        let lines = csvLines(HealthCSVExportGenerator.bodyCSV(rows: [row], timeZone: tokyo))
        XCTAssertEqual(lines[1], "2026-10-12T07:05:00+09:00,weight_kg,72.4,kg,eufy Life")
    }

    /// 別タイムゾーンでもオフセットが正しく付く（UTCなら `Z`）。
    func test_iso8601_respectsProvidedTimezone() {
        let row = HealthBodyCSVRow(
            recordedAt: makeDate(2026, 10, 12, 7, 5, 0),
            metric: .bmi,
            value: 23,
            source: "eufy Life"
        )
        let utcLines = csvLines(HealthCSVExportGenerator.bodyCSV(rows: [row], timeZone: TimeZone(identifier: "UTC")!))
        XCTAssertEqual(utcLines[1], "2026-10-11T22:05:00Z,bmi,23,count,eufy Life")
    }

    // MARK: - 日次サマリー（縦持ち）

    func test_dailyCSV_columnOrder_isDateMetricValueUnitSource() {
        let row = makeDailyRow(metric: .steps, value: 12345)
        let lines = csvLines(HealthCSVExportGenerator.dailyCSV(rows: [row], timeZone: tokyo))
        XCTAssertEqual(lines[0], "date,metric,value,unit,source")
        XCTAssertEqual(lines[1], "2026-10-12,steps,12345,count,Garmin")
    }

    func test_dailyCSV_date_isLocalYYYYMMDD() {
        let row = HealthDailyMetricCSVRow(
            date: makeDate(2026, 1, 2, 0, 0, 0),
            metric: .flightsClimbed,
            value: 7,
            source: "iPhone"
        )
        let lines = csvLines(HealthCSVExportGenerator.dailyCSV(rows: [row], timeZone: tokyo))
        XCTAssertEqual(lines[1], "2026-01-02,flights_climbed,7,count,iPhone")
    }

    /// 全ての日次指標が仕様どおりの metric / unit で出る。
    func test_dailyCSV_allMetrics_haveSpecifiedNamesAndUnits() {
        let expected: [HealthDailyMetric: String] = [
            .restingHeartRate: "resting_heart_rate,bpm",
            .steps: "steps,count",
            .distanceKm: "distance_km,km",
            .activeEnergyKcal: "active_energy_kcal,kcal",
            .basalEnergyKcal: "basal_energy_kcal,kcal",
            .flightsClimbed: "flights_climbed,count"
        ]
        XCTAssertEqual(HealthDailyMetric.allCases.count, expected.count)

        for metric in HealthDailyMetric.allCases {
            let lines = csvLines(
                HealthCSVExportGenerator.dailyCSV(rows: [makeDailyRow(metric: metric, value: 1)], timeZone: tokyo)
            )
            XCTAssertEqual(
                lines[1],
                "2026-10-12,\(expected[metric]!),1,Garmin",
                "metric \(metric) should emit `metric,unit` as \(expected[metric]!)"
            )
        }
    }

    func test_bodyCSV_allMetrics_haveSpecifiedNamesAndUnits() {
        let expected: [HealthBodyMetric: String] = [
            .weightKg: "weight_kg,kg",
            .bodyFatPercentage: "body_fat_percentage,percent",
            .leanBodyMassKg: "lean_body_mass_kg,kg",
            .bmi: "bmi,count"
        ]
        XCTAssertEqual(HealthBodyMetric.allCases.count, expected.count)

        for metric in HealthBodyMetric.allCases {
            let row = HealthBodyCSVRow(
                recordedAt: makeDate(2026, 10, 12, 7, 0, 0),
                metric: metric,
                value: 10,
                source: "eufy Life"
            )
            let lines = csvLines(HealthCSVExportGenerator.bodyCSV(rows: [row], timeZone: tokyo))
            XCTAssertEqual(lines[1], "2026-10-12T07:00:00+09:00,\(expected[metric]!),10,eufy Life")
        }
    }

    /// 同じ date × metric で source が違う行は**両方出す**。
    /// 歩数は iPhone 本体と Garmin の両方が書くため、どちらが正しいかは BodyOps 側では決めない。
    func test_dailyCSV_sameDateAndMetric_withDifferentSources_emitsBothRows() {
        let date = makeDate(2026, 10, 12, 0, 0, 0)
        let rows = [
            HealthDailyMetricCSVRow(date: date, metric: .steps, value: 8200, source: "iPhone"),
            HealthDailyMetricCSVRow(date: date, metric: .steps, value: 9150, source: "Garmin")
        ]
        let lines = csvLines(HealthCSVExportGenerator.dailyCSV(rows: rows, timeZone: tokyo))

        XCTAssertEqual(lines.count, 3, "同じ date × metric でも source ごとに行が出るべき")
        XCTAssertEqual(lines[1], "2026-10-12,steps,8200,count,iPhone")
        XCTAssertEqual(lines[2], "2026-10-12,steps,9150,count,Garmin")
    }

    // MARK: - RFC4180 エスケープ（source 名はアプリ名なのでカンマや引用符を含みうる）

    func test_dailyCSV_sourceWithComma_isQuoted() {
        let row = makeDailyRow(metric: .steps, value: 100, source: "Garmin Connect, Inc.")
        let lines = csvLines(HealthCSVExportGenerator.dailyCSV(rows: [row], timeZone: tokyo))
        XCTAssertEqual(lines[1], "2026-10-12,steps,100,count,\"Garmin Connect, Inc.\"")
    }

    func test_dailyCSV_sourceWithQuotes_isDoubledAndQuoted() {
        let row = makeDailyRow(metric: .steps, value: 100, source: "My \"Best\" App")
        let lines = csvLines(HealthCSVExportGenerator.dailyCSV(rows: [row], timeZone: tokyo))
        XCTAssertEqual(lines[1], "2026-10-12,steps,100,count,\"My \"\"Best\"\" App\"")
    }

    func test_sleepCSV_sourceWithNewline_isQuoted() {
        let row = HealthSleepCSVRow(
            start: makeDate(2026, 10, 12, 23, 0, 0),
            end: makeDate(2026, 10, 13, 6, 0, 0),
            stage: .asleepCore,
            source: "Line1\nLine2"
        )
        let csv = HealthCSVExportGenerator.sleepCSV(rows: [row], timeZone: tokyo)
        XCTAssertTrue(csv.contains("\"Line1\nLine2\""), "newline in source must be quoted: \(csv)")
    }

    func test_bodyCSV_sourceWithCommaQuoteAndNewline_isFullyEscaped() {
        let row = HealthBodyCSVRow(
            recordedAt: makeDate(2026, 10, 12, 7, 0, 0),
            metric: .bodyFatPercentage,
            value: 18.5,
            source: "eufy, \"Life\"\nApp"
        )
        let csv = HealthCSVExportGenerator.bodyCSV(rows: [row], timeZone: tokyo)
        XCTAssertTrue(
            csv.contains("\"eufy, \"\"Life\"\"\nApp\""),
            "commas, quotes and newlines must all be RFC4180 escaped: \(csv)"
        )
    }

    func test_sourceWithoutSpecialCharacters_isNotQuoted() {
        let row = makeDailyRow(metric: .steps, value: 100, source: "Garmin")
        let lines = csvLines(HealthCSVExportGenerator.dailyCSV(rows: [row], timeZone: tokyo))
        XCTAssertFalse(lines[1].contains("\""), "特殊文字が無い source は引用符で囲まない: \(lines[1])")
    }

    // MARK: - 数値の整形

    func test_formatValue_integralValues_haveNoDecimalPoint() {
        XCTAssertEqual(HealthCSVExportGenerator.formatValue(12345), "12345")
        XCTAssertEqual(HealthCSVExportGenerator.formatValue(0), "0")
        XCTAssertEqual(HealthCSVExportGenerator.formatValue(-3), "-3")
    }

    func test_formatValue_fractionalValues_dropTrailingZeros() {
        XCTAssertEqual(HealthCSVExportGenerator.formatValue(72.4), "72.4")
        XCTAssertEqual(HealthCSVExportGenerator.formatValue(18.55), "18.55")
        XCTAssertEqual(HealthCSVExportGenerator.formatValue(5.1230), "5.123")
    }

    func test_formatValue_nonFiniteValues_areEmpty() {
        XCTAssertEqual(HealthCSVExportGenerator.formatValue(.nan), "")
        XCTAssertEqual(HealthCSVExportGenerator.formatValue(.infinity), "")
    }

    // MARK: - 365日の保持期間

    func test_retentionDays_is365() {
        XCTAssertEqual(HealthCSVExportGenerator.retentionDays, 365)
    }

    /// 365日より古いサンプルは3種類すべてから除外される。
    func test_filterByRetention_excludesSamplesOlderThan365Days() {
        let now = makeDate(2026, 10, 12, 12, 0, 0)
        let recent = now.addingTimeInterval(-10 * 86_400)        // 10日前 → 残る
        let justInside = now.addingTimeInterval(-364 * 86_400)   // 364日前 → 残る
        let tooOld = now.addingTimeInterval(-400 * 86_400)       // 400日前 → 落ちる

        let snapshot = HealthImportSnapshot(
            sleepRows: [
                HealthSleepCSVRow(start: recent, end: recent, stage: .asleepCore, source: "Garmin"),
                HealthSleepCSVRow(start: tooOld, end: tooOld, stage: .asleepCore, source: "Garmin")
            ],
            dailyRows: [
                HealthDailyMetricCSVRow(date: justInside, metric: .steps, value: 1, source: "Garmin"),
                HealthDailyMetricCSVRow(date: tooOld, metric: .steps, value: 2, source: "Garmin")
            ],
            bodyRows: [
                HealthBodyCSVRow(recordedAt: recent, metric: .weightKg, value: 70, source: "eufy Life"),
                HealthBodyCSVRow(recordedAt: tooOld, metric: .weightKg, value: 80, source: "eufy Life")
            ]
        )

        let filtered = HealthCSVExportGenerator.filterByRetention(snapshot: snapshot, now: now)

        XCTAssertEqual(filtered.sleepRows.count, 1)
        XCTAssertEqual(filtered.sleepRows.first?.start, recent)
        XCTAssertEqual(filtered.dailyRows.count, 1)
        XCTAssertEqual(filtered.dailyRows.first?.value, 1)
        XCTAssertEqual(filtered.bodyRows.count, 1)
        XCTAssertEqual(filtered.bodyRows.first?.value, 70)
        XCTAssertEqual(filtered.totalRowCount, 3)
    }

    func test_filterByRetention_withAllSamplesTooOld_producesEmptySnapshot() {
        let now = makeDate(2026, 10, 12, 12, 0, 0)
        let tooOld = now.addingTimeInterval(-500 * 86_400)
        let snapshot = HealthImportSnapshot(
            sleepRows: [HealthSleepCSVRow(start: tooOld, end: tooOld, stage: .awake, source: "Garmin")],
            dailyRows: [HealthDailyMetricCSVRow(date: tooOld, metric: .steps, value: 1, source: "Garmin")],
            bodyRows: [HealthBodyCSVRow(recordedAt: tooOld, metric: .bmi, value: 22, source: "eufy Life")]
        )

        let filtered = HealthCSVExportGenerator.filterByRetention(snapshot: snapshot, now: now)

        XCTAssertTrue(filtered.isEmpty)
        // 0件でもヘッダ行だけのCSVになる
        XCTAssertEqual(
            HealthCSVExportGenerator.sleepCSV(rows: filtered.sleepRows),
            HealthCSVExportGenerator.sleepHeader + "\r\n"
        )
    }

    func test_retentionStartDate_is365DaysBeforeNow() {
        let now = makeDate(2026, 10, 12, 12, 0, 0)
        let start = HealthCSVExportGenerator.retentionStartDate(now: now)
        XCTAssertEqual(now.timeIntervalSince(start), 365 * 86_400, accuracy: 1)
    }

    // MARK: - Helpers

    private let tokyo = TimeZone(identifier: "Asia/Tokyo")!

    private func csvLines(_ csv: String) -> [String] {
        csv.components(separatedBy: "\r\n").dropLast().map(String.init)
    }

    private func makeDailyRow(
        metric: HealthDailyMetric,
        value: Double,
        source: String = "Garmin"
    ) -> HealthDailyMetricCSVRow {
        HealthDailyMetricCSVRow(
            date: makeDate(2026, 10, 12, 0, 0, 0),
            metric: metric,
            value: value,
            source: source
        )
    }

    /// Asia/Tokyo 固定で Date を作る（実行環境のタイムゾーンに結果が依存しないように）
    private func makeDate(_ year: Int, _ month: Int, _ day: Int, _ hour: Int, _ minute: Int, _ second: Int) -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = tokyo
        return calendar.date(
            from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
        )!
    }
}

/// ヘルスケアCSVが既存の筋トレ・食事CSVと同じ Documents/ 配下に書かれ、
/// 既存ファイルの仕様・内容を壊さないことを確認する。
final class ICloudCSVWriterHealthTests: XCTestCase {

    func test_write_withHealthSnapshot_writesThreeHealthCSVsIntoDocuments() throws {
        let container = makeTemporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let snapshot = HealthImportSnapshot(
            sleepRows: [
                HealthSleepCSVRow(start: Date(), end: Date(), stage: .asleepDeep, source: "Garmin")
            ],
            dailyRows: [
                HealthDailyMetricCSVRow(date: Date(), metric: .steps, value: 8200, source: "iPhone")
            ],
            bodyRows: [
                HealthBodyCSVRow(recordedAt: Date(), metric: .weightKg, value: 72.4, source: "eufy Life")
            ]
        )

        let outcome = ICloudCSVWriter.write(
            workoutRows: [],
            mealRows: [],
            healthSnapshot: snapshot,
            containerIdentifier: ICloudExportService.containerIdentifier,
            containerURLProvider: { _ in container }
        )

        XCTAssertEqual(outcome, .success)
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        for name in ["bodyops_health_sleep.csv", "bodyops_health_daily.csv", "bodyops_health_body.csv"] {
            let url = documents.appendingPathComponent(name)
            XCTAssertTrue(FileManager.default.fileExists(atPath: url.path), "\(name) should exist")
            let content = try String(contentsOf: url, encoding: .utf8)
            XCTAssertTrue(content.hasSuffix("\r\n"), "\(name) should use CRLF line endings")
            XCTAssertEqual(content.components(separatedBy: "\r\n").filter { !$0.isEmpty }.count, 2)
        }
        // コンテナ直下には作らない（直下だと Finder / 「ファイル」アプリに出ない）
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: container.appendingPathComponent("bodyops_health_sleep.csv").path)
        )
    }

    /// 0件のスナップショットでも、ヘッダ行だけのファイルを必ず作る。
    func test_write_withEmptyHealthSnapshot_writesHeaderOnlyFiles() throws {
        let container = makeTemporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let outcome = ICloudCSVWriter.write(
            workoutRows: [],
            mealRows: [],
            healthSnapshot: HealthImportSnapshot(),
            containerIdentifier: ICloudExportService.containerIdentifier,
            containerURLProvider: { _ in container }
        )

        XCTAssertEqual(outcome, .success)
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        XCTAssertEqual(
            try String(contentsOf: documents.appendingPathComponent("bodyops_health_sleep.csv"), encoding: .utf8),
            HealthCSVExportGenerator.sleepHeader + "\r\n"
        )
        XCTAssertEqual(
            try String(contentsOf: documents.appendingPathComponent("bodyops_health_daily.csv"), encoding: .utf8),
            HealthCSVExportGenerator.dailyHeader + "\r\n"
        )
        XCTAssertEqual(
            try String(contentsOf: documents.appendingPathComponent("bodyops_health_body.csv"), encoding: .utf8),
            HealthCSVExportGenerator.bodyHeader + "\r\n"
        )
    }

    /// ヘルスケアを渡さない（nil）ときはヘルスケアCSVを作らず、既存CSVだけを更新する。
    func test_write_withoutHealthSnapshot_doesNotCreateHealthCSVs() throws {
        let container = makeTemporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        let outcome = ICloudCSVWriter.write(
            workoutRows: [],
            mealRows: [],
            healthSnapshot: nil,
            containerIdentifier: ICloudExportService.containerIdentifier,
            containerURLProvider: { _ in container }
        )

        XCTAssertEqual(outcome, .success)
        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        XCTAssertFalse(
            FileManager.default.fileExists(atPath: documents.appendingPathComponent("bodyops_health_sleep.csv").path)
        )
        // 既存の筋トレ・食事CSVは変わらず書かれている
        XCTAssertEqual(
            try String(contentsOf: documents.appendingPathComponent("bodyops_workouts.csv"), encoding: .utf8),
            CSVExportGenerator.workoutsHeader + "\r\n"
        )
    }

    /// 回帰防止: ヘルスケアCSVを追加しても既存CSVの仕様・内容は変わらない。
    func test_write_withHealthSnapshot_leavesExistingCSVSpecUnchanged() throws {
        let container = makeTemporaryContainer()
        defer { try? FileManager.default.removeItem(at: container) }

        _ = ICloudCSVWriter.write(
            workoutRows: [],
            mealRows: [],
            healthSnapshot: HealthImportSnapshot(),
            containerIdentifier: ICloudExportService.containerIdentifier,
            containerURLProvider: { _ in container }
        )

        let documents = container.appendingPathComponent("Documents", isDirectory: true)
        XCTAssertEqual(
            try String(contentsOf: documents.appendingPathComponent("bodyops_workouts.csv"), encoding: .utf8),
            CSVExportGenerator.workoutsHeader + "\r\n"
        )
        XCTAssertEqual(
            try String(contentsOf: documents.appendingPathComponent("bodyops_meals.csv"), encoding: .utf8),
            CSVExportGenerator.mealsHeader + "\r\n"
        )
    }

    /// iCloudが使えない環境では、ヘルスケアを渡しても即座に .unavailable を返す。
    func test_write_withUnavailableContainer_returnsUnavailable() {
        let outcome = ICloudCSVWriter.write(
            workoutRows: [],
            mealRows: [],
            healthSnapshot: HealthImportSnapshot(),
            containerIdentifier: ICloudExportService.containerIdentifier,
            containerURLProvider: { _ in nil }
        )
        XCTAssertEqual(outcome, .unavailable)
    }

    private func makeTemporaryContainer() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
    }
}
