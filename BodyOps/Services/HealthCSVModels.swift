import Foundation

/// 睡眠ステージ。HealthKit の `HKCategoryValueSleepAnalysis` を CSV 用の安定した文字列に対応づける。
enum HealthSleepStage: String, Sendable, Equatable, CaseIterable {
    case inBed = "in_bed"
    case asleepUnspecified = "asleep_unspecified"
    case asleepCore = "asleep_core"
    case asleepDeep = "asleep_deep"
    case asleepREM = "asleep_rem"
    case awake = "awake"

    /// CSV の `stage` 列に出す値
    var csvValue: String { rawValue }
}

/// 日次サマリー指標。CSV の `metric` 列と `unit` 列を型として持つ。
enum HealthDailyMetric: String, Sendable, Equatable, CaseIterable {
    case restingHeartRate = "resting_heart_rate"
    case steps
    case distanceKm = "distance_km"
    case activeEnergyKcal = "active_energy_kcal"
    case basalEnergyKcal = "basal_energy_kcal"
    case flightsClimbed = "flights_climbed"

    var csvValue: String { rawValue }

    var unit: String {
        switch self {
        case .restingHeartRate: return "bpm"
        case .steps, .flightsClimbed: return "count"
        case .distanceKm: return "km"
        case .activeEnergyKcal, .basalEnergyKcal: return "kcal"
        }
    }
}

/// 体組成指標。
enum HealthBodyMetric: String, Sendable, Equatable, CaseIterable {
    case weightKg = "weight_kg"
    case bodyFatPercentage = "body_fat_percentage"
    case leanBodyMassKg = "lean_body_mass_kg"
    case bmi

    var csvValue: String { rawValue }

    var unit: String {
        switch self {
        case .weightKg, .leanBodyMassKg: return "kg"
        case .bodyFatPercentage: return "percent"
        case .bmi: return "count"
        }
    }
}

/// 睡眠区間1件。日ごとに合算せず、HealthKit から取れた区間のままを保持する。
struct HealthSleepCSVRow: Sendable, Equatable {
    let start: Date
    let end: Date
    let stage: HealthSleepStage
    /// `HKSource.name` をそのまま入れる（どのアプリ由来かを learning_coach 側で選べるようにするため）
    let source: String
}

/// 日次サマリー1件（1行1指標の縦持ち）。
struct HealthDailyMetricCSVRow: Sendable, Equatable {
    /// ローカル日付の起点（CSV には `yyyy-MM-dd` で出す）
    let date: Date
    let metric: HealthDailyMetric
    let value: Double
    let source: String
}

/// 体組成1件。
struct HealthBodyCSVRow: Sendable, Equatable {
    let recordedAt: Date
    let metric: HealthBodyMetric
    let value: Double
    let source: String
}

/// HealthKit から読み取った結果のスナップショット。
/// SwiftData も HealthKit の型も含まない Sendable な値なので、アクター境界を安全に越えられる。
struct HealthImportSnapshot: Sendable, Equatable {
    var sleepRows: [HealthSleepCSVRow] = []
    var dailyRows: [HealthDailyMetricCSVRow] = []
    var bodyRows: [HealthBodyCSVRow] = []

    var totalRowCount: Int { sleepRows.count + dailyRows.count + bodyRows.count }
    var isEmpty: Bool { totalRowCount == 0 }
}
