import Foundation
import SwiftData
import SwiftUI

/// iCloud Documentsコンテナへの書き込み結果
enum ICloudCSVWriteOutcome: Sendable, Equatable {
    case success
    case unavailable
    case failure
}

/// iCloud Documentsコンテナへのファイル書き込みだけを担う層。
/// FileManagerを差し替え可能にしてあり、iCloudが未設定/未サインインの環境（CI・シミュレータ等）でも
/// ネットワークアクセスやクラッシュなしに `.unavailable` を返すだけで静かに終わる。
enum ICloudCSVWriter {
    static func write(
        workoutRows: [WorkoutSetCSVRow],
        mealRows: [MealRecordCSVRow],
        containerIdentifier: String,
        fileManager: FileManager = .default,
        containerURLProvider: @Sendable (String) -> URL? = { identifier in
            FileManager.default.url(forUbiquityContainerIdentifier: identifier)
        }
    ) -> ICloudCSVWriteOutcome {
        write(
            workoutRows: workoutRows,
            mealRows: mealRows,
            healthSnapshot: nil,
            containerIdentifier: containerIdentifier,
            fileManager: fileManager,
            containerURLProvider: containerURLProvider
        )
    }

    /// ヘルスケア分を含めた書き出し。
    /// `healthSnapshot` が nil のときはヘルスケアCSVを作らない（既存の筋トレ・食事CSVだけを更新する）。
    /// 0件のスナップショットを渡した場合は**ヘッダ行だけのCSVを作る**
    /// （取り込み側が「ファイルが無い」と「データが0件」を区別できるように）。
    static func write(
        workoutRows: [WorkoutSetCSVRow],
        mealRows: [MealRecordCSVRow],
        healthSnapshot: HealthImportSnapshot?,
        containerIdentifier: String,
        fileManager: FileManager = .default,
        containerURLProvider: @Sendable (String) -> URL? = { identifier in
            FileManager.default.url(forUbiquityContainerIdentifier: identifier)
        }
    ) -> ICloudCSVWriteOutcome {
        guard let containerURL = containerURLProvider(containerIdentifier) else {
            return .unavailable
        }
        do {
            // Finder の iCloud Drive や iPhone の「ファイル」アプリに公開されるのは
            // Documents サブディレクトリの中身だけなので、CSV は必ずその配下に置く。
            // withIntermediateDirectories: true は既存ディレクトリでもエラーにならず、
            // 既にある Documents とその中身を削除・上書きすることもない。
            let documentsURL = containerURL.appendingPathComponent("Documents", isDirectory: true)
            try fileManager.createDirectory(at: documentsURL, withIntermediateDirectories: true)
            let workoutsURL = documentsURL.appendingPathComponent("bodyops_workouts.csv")
            let mealsURL = documentsURL.appendingPathComponent("bodyops_meals.csv")
            try CSVExportGenerator.workoutsCSV(rows: workoutRows).write(to: workoutsURL, atomically: true, encoding: .utf8)
            try CSVExportGenerator.mealsCSV(rows: mealRows).write(to: mealsURL, atomically: true, encoding: .utf8)
            if let healthSnapshot {
                try HealthCSVExportGenerator.sleepCSV(rows: healthSnapshot.sleepRows).write(
                    to: documentsURL.appendingPathComponent("bodyops_health_sleep.csv"),
                    atomically: true,
                    encoding: .utf8
                )
                try HealthCSVExportGenerator.dailyCSV(rows: healthSnapshot.dailyRows).write(
                    to: documentsURL.appendingPathComponent("bodyops_health_daily.csv"),
                    atomically: true,
                    encoding: .utf8
                )
                try HealthCSVExportGenerator.bodyCSV(rows: healthSnapshot.bodyRows).write(
                    to: documentsURL.appendingPathComponent("bodyops_health_body.csv"),
                    atomically: true,
                    encoding: .utf8
                )
            }
            return .success
        } catch {
            return .failure
        }
    }
}

/// 設定画面に表示する書き出しステータス
struct ICloudExportStatus: Sendable, Equatable {
    var isICloudAvailable: Bool = false
    var lastExportDate: Date?
    var lastWorkoutRowCount: Int = 0
    var lastMealRowCount: Int = 0
    /// 直近に読み込んだ睡眠区間の件数
    var lastHealthSleepRowCount: Int = 0
    /// 直近に読み込んだ日次サマリーの件数
    var lastHealthDailyRowCount: Int = 0
    /// 直近に読み込んだ体組成の件数
    var lastHealthBodyRowCount: Int = 0
    /// HealthKit がこの端末で使えるか
    var isHealthKitAvailable: Bool = false
    /// 権限要求が失敗したときのメッセージ（黙って失敗しないために画面へ出す）
    var healthKitErrorMessage: String?
}

/// 全トレーニング・食事記録をiCloud Drive（Documentsコンテナ）にCSVとして書き出すサービス。
///
/// - 保存のたびに呼び出し、短時間の連続呼び出しはdebounceして1回の書き出しにまとめる
/// - スナップショット取得（MainActor・SwiftDataモデル→Sendable構造体変換）は同期的に行うが軽量。
///   実際のファイルI/OはTask.detachedでMainActor外に逃がし、ローカル保存をブロックしない
/// - iCloudが使えない場合は静かに失敗し、機能や既存データに一切影響しない
@MainActor
@Observable
final class ICloudExportService {
    static let shared = ICloudExportService()

    static let containerIdentifier = "iCloud.com.bodyops.app"

    private static let debounceSeconds: Double = 2
    private static let enabledDefaultsKey = "icloudExportEnabled"
    private static let lastExportDateDefaultsKey = "icloudExportLastDate"
    private static let healthKitEnabledDefaultsKey = "healthKitImportEnabled"

    private(set) var status = ICloudExportStatus()

    var isEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isEnabled, forKey: Self.enabledDefaultsKey)
        }
    }

    /// Apple ヘルスケアから読み込むか。既定 OFF。
    /// OFF→ON のときに HealthKit の権限ダイアログを出すのは呼び出し側（UI）の責務。
    var isHealthKitImportEnabled: Bool {
        didSet {
            UserDefaults.standard.set(isHealthKitImportEnabled, forKey: Self.healthKitEnabledDefaultsKey)
            if !isHealthKitImportEnabled {
                status.healthKitErrorMessage = nil
            }
        }
    }

    private var debounceTask: Task<Void, Never>?

    private init() {
        isEnabled = UserDefaults.standard.bool(forKey: Self.enabledDefaultsKey)
        isHealthKitImportEnabled = UserDefaults.standard.bool(forKey: Self.healthKitEnabledDefaultsKey)
        if let stored = UserDefaults.standard.object(forKey: Self.lastExportDateDefaultsKey) as? Date {
            status.lastExportDate = stored
        }
    }

    /// 保存直後に呼ぶ debounce 付きの書き出しトリガー。無効化されていれば何もしない。
    /// スナップショットのみ同期的に取ってすぐ返るため、呼び出し元の保存処理をブロックしない。
    func scheduleExport(context: ModelContext) {
        guard isEnabled else { return }
        let workoutRows = Self.snapshotWorkoutRows(context: context)
        let mealRows = Self.snapshotMealRows(context: context)

        debounceTask?.cancel()
        debounceTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(Self.debounceSeconds))
            guard !Task.isCancelled else { return }
            guard let self else { return }
            let healthSnapshot = await self.importHealthSnapshotIfEnabled()
            guard !Task.isCancelled else { return }
            await self.performExport(
                workoutRows: workoutRows,
                mealRows: mealRows,
                healthSnapshot: healthSnapshot
            )
        }
    }

    /// 設定画面の手動書き出し用。debounceせず即座に実行する。
    func exportNow(context: ModelContext) async {
        debounceTask?.cancel()
        let workoutRows = Self.snapshotWorkoutRows(context: context)
        let mealRows = Self.snapshotMealRows(context: context)
        // 筋トレ・食事と一緒にヘルスケア分も読み込んで書き出す。
        let healthSnapshot = await importHealthSnapshotIfEnabled()
        await performExport(workoutRows: workoutRows, mealRows: mealRows, healthSnapshot: healthSnapshot)
    }

    /// iCloudの利用可否だけを再チェックする（設定画面の表示用）
    func refreshAvailability() async {
        let identifier = Self.containerIdentifier
        let available = await Task.detached(priority: .utility) {
            FileManager.default.url(forUbiquityContainerIdentifier: identifier) != nil
        }.value
        status.isICloudAvailable = available
        status.isHealthKitAvailable = HealthKitImportService.shared.isHealthDataAvailable
    }

    /// HealthKit の読み取り権限ダイアログを出す。トグルを OFF→ON にしたときに呼ぶ。
    ///
    /// HealthKit は仕様上「読み取りを許可されているか」をアプリから判定できない（拒否と0件が区別できない）。
    /// そのためここで分かるのは「ダイアログを出せたか」だけで、失敗したときだけ画面に理由を出す。
    func requestHealthKitAuthorization() async {
        let outcome = await HealthKitImportService.shared.requestAuthorization()
        switch outcome {
        case .requested:
            status.isHealthKitAvailable = true
            status.healthKitErrorMessage = nil
        case .unavailable:
            status.isHealthKitAvailable = false
            status.healthKitErrorMessage = "この端末ではApple ヘルスケアを利用できません"
        case .failed(let message):
            status.healthKitErrorMessage = "Apple ヘルスケアの許可を取得できませんでした: \(message)"
        }
    }

    // MARK: - Private

    /// ヘルスケア読み込みが有効なら読み、無効なら nil（＝ヘルスケアCSVを触らない）。
    private func importHealthSnapshotIfEnabled() async -> HealthImportSnapshot? {
        guard isHealthKitImportEnabled else { return nil }
        return await HealthKitImportService.shared.importSnapshot()
    }

    private func performExport(
        workoutRows: [WorkoutSetCSVRow],
        mealRows: [MealRecordCSVRow],
        healthSnapshot: HealthImportSnapshot?
    ) async {
        let identifier = Self.containerIdentifier
        let outcome = await Task.detached(priority: .utility) {
            ICloudCSVWriter.write(
                workoutRows: workoutRows,
                mealRows: mealRows,
                healthSnapshot: healthSnapshot,
                containerIdentifier: identifier
            )
        }.value

        switch outcome {
        case .success:
            let now = Date()
            status.isICloudAvailable = true
            status.lastExportDate = now
            status.lastWorkoutRowCount = workoutRows.count
            status.lastMealRowCount = mealRows.count
            if let healthSnapshot {
                status.lastHealthSleepRowCount = healthSnapshot.sleepRows.count
                status.lastHealthDailyRowCount = healthSnapshot.dailyRows.count
                status.lastHealthBodyRowCount = healthSnapshot.bodyRows.count
            }
            UserDefaults.standard.set(now, forKey: Self.lastExportDateDefaultsKey)
        case .unavailable:
            status.isICloudAvailable = false
        case .failure:
            break
        }
    }

    // MARK: - Snapshotting
    // SwiftDataモデルはMainActor上でのみ触り、Sendableな構造体に変換してからアクター境界を越える。

    private static func snapshotWorkoutRows(context: ModelContext) -> [WorkoutSetCSVRow] {
        let descriptor = FetchDescriptor<WorkoutSession>(sortBy: [SortDescriptor(\.date)])
        let sessions = (try? context.fetch(descriptor)) ?? []
        return CSVExportGenerator.workoutRows(from: sessions)
    }

    private static func snapshotMealRows(context: ModelContext) -> [MealRecordCSVRow] {
        let descriptor = FetchDescriptor<MealRecord>(sortBy: [SortDescriptor(\.recordedAt)])
        let meals = (try? context.fetch(descriptor)) ?? []
        return CSVExportGenerator.mealRows(from: meals)
    }
}
