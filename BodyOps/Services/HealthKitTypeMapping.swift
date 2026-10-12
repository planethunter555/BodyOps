#if canImport(HealthKit)
import Foundation
import HealthKit

/// HealthKit の型・単位・カテゴリ値と BodyOps の CSV 指標との対応づけ。
///
/// `HealthKitImportService` は `@MainActor` なので、その static メンバも MainActor 隔離される。
/// HealthKit のクエリ完了ハンドラは MainActor 外で呼ばれるため、ハンドラ内から参照する対応表と
/// 変換関数は**ここに切り出して nonisolated にしておく**（Swift 6 の strict concurrency 対策）。
/// あわせて HealthKit に依存しない純粋な変換としてテストもしやすくなる。
enum HealthKitTypeMapping {

    /// 日次サマリー: HealthKit識別子 → CSV指標
    static let dailyQuantityIdentifiers: [HKQuantityTypeIdentifier: HealthDailyMetric] = [
        .restingHeartRate: .restingHeartRate,
        .stepCount: .steps,
        .distanceWalkingRunning: .distanceKm,
        .activeEnergyBurned: .activeEnergyKcal,
        .basalEnergyBurned: .basalEnergyKcal,
        .flightsClimbed: .flightsClimbed
    ]

    /// 体組成: HealthKit識別子 → CSV指標
    static let bodyQuantityIdentifiers: [HKQuantityTypeIdentifier: HealthBodyMetric] = [
        .bodyMass: .weightKg,
        .bodyFatPercentage: .bodyFatPercentage,
        .leanBodyMass: .leanBodyMassKg,
        .bodyMassIndex: .bmi
    ]

    /// 読み取りを要求する型の集合。**書き込み用の型は一切含めない**（BodyOps は HealthKit に書き込まない）。
    static func readTypes() -> Set<HKObjectType> {
        var types = Set<HKObjectType>()
        if let sleep = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) {
            types.insert(sleep)
        }
        for identifier in dailyQuantityIdentifiers.keys {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        for identifier in bodyQuantityIdentifiers.keys {
            if let type = HKObjectType.quantityType(forIdentifier: identifier) {
                types.insert(type)
            }
        }
        return types
    }

    static func unit(for metric: HealthDailyMetric) -> HKUnit {
        switch metric {
        case .restingHeartRate: return HKUnit.count().unitDivided(by: .minute())
        case .steps, .flightsClimbed: return .count()
        case .distanceKm: return HKUnit.meterUnit(with: .kilo)
        case .activeEnergyKcal, .basalEnergyKcal: return .kilocalorie()
        }
    }

    static func unit(for metric: HealthBodyMetric) -> HKUnit {
        switch metric {
        case .weightKg, .leanBodyMassKg: return HKUnit.gramUnit(with: .kilo)
        case .bodyFatPercentage: return .percent()
        case .bmi: return .count()
        }
    }

    /// `HKUnit.percent()` は 0〜1 を返すので、CSV の `percent` 単位に合わせる倍率。
    static func valueScale(for metric: HealthBodyMetric) -> Double {
        metric == .bodyFatPercentage ? 100 : 1
    }

    /// 平均で集計すべき指標（安静時心拍）か、合計で集計すべき指標（歩数・距離・カロリー・階数）か。
    static func isAveraged(_ metric: HealthDailyMetric) -> Bool {
        metric == .restingHeartRate
    }

    static func statisticsOptions(for metric: HealthDailyMetric) -> HKStatisticsOptions {
        // .separateBySource を付けることで、同じ日に複数アプリ（iPhone本体 / Garmin 等）が書いた値を
        // source ごとに取り出せる。どちらが正しいかは BodyOps 側では決めず全部出す。
        isAveraged(metric)
            ? [.discreteAverage, .separateBySource]
            : [.cumulativeSum, .separateBySource]
    }

    /// `HKCategoryValueSleepAnalysis` → CSV用ステージ。
    /// 未知の値は `nil` にして落とす（取れないものを取れたように見せない）。
    static func sleepStage(forCategoryValue value: Int) -> HealthSleepStage? {
        switch HKCategoryValueSleepAnalysis(rawValue: value) {
        case .inBed: return .inBed
        case .asleepUnspecified: return .asleepUnspecified
        case .asleepCore: return .asleepCore
        case .asleepDeep: return .asleepDeep
        case .asleepREM: return .asleepREM
        case .awake: return .awake
        default: return nil
        }
    }
}
#endif
