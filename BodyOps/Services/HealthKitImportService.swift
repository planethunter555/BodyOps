import Foundation
#if canImport(HealthKit)
import HealthKit
#endif

/// HealthKit の権限要求の結果。
///
/// HealthKit は**プライバシー保護のため「読み取りを許可されているか」をアプリから判定できない**
/// （拒否とデータ0件が区別できない）。そのため `.requested` は「ダイアログの提示が完了した」ことしか意味しない。
enum HealthKitAuthorizationOutcome: Sendable, Equatable {
    /// 権限ダイアログの提示が完了した（許可されたとは限らない）
    case requested
    /// この端末では HealthKit が使えない
    case unavailable
    /// 権限要求自体が失敗した
    case failed(String)
}

/// Apple ヘルスケア（HealthKit）から睡眠・日次サマリー・体組成を**読み取るだけ**のサービス。
///
/// - **読み取り専用**。`HKHealthStore.save` / `delete` は一切呼ばない（`toShare` は常に空集合）
/// - ネットワーク通信は行わない。Garmin / eufy の API も直接叩かない（すべて HealthKit 経由）
/// - 取得結果は Sendable な `HealthImportSnapshot` に変換してから返すため、
///   HealthKit の非Sendableな型がアクター境界を越えない
/// - HealthKit が使えない環境では空スナップショットを返して静かに終わる
@MainActor
final class HealthKitImportService {
    static let shared = HealthKitImportService()

    #if canImport(HealthKit)
    private let store = HKHealthStore()
    #endif

    private init() {}

    /// この端末で HealthKit が利用可能か
    var isHealthDataAvailable: Bool {
        #if canImport(HealthKit)
        return HKHealthStore.isHealthDataAvailable()
        #else
        return false
        #endif
    }

    /// 読み取り権限を要求する。**書き込み権限は要求しない**。
    func requestAuthorization() async -> HealthKitAuthorizationOutcome {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return .unavailable }
        let readTypes = HealthKitTypeMapping.readTypes()
        guard !readTypes.isEmpty else { return .unavailable }
        do {
            // toShare は空集合。BodyOps は HealthKit に書き込まない。
            try await store.requestAuthorization(toShare: [], read: readTypes)
            return .requested
        } catch {
            return .failed(error.localizedDescription)
        }
        #else
        return .unavailable
        #endif
    }

    /// 直近 `HealthCSVExportGenerator.retentionDays` 日分の睡眠・日次サマリー・体組成を読み取る。
    func importSnapshot(now: Date = Date()) async -> HealthImportSnapshot {
        #if canImport(HealthKit)
        guard HKHealthStore.isHealthDataAvailable() else { return HealthImportSnapshot() }
        let start = HealthCSVExportGenerator.retentionStartDate(now: now)

        let snapshot = HealthImportSnapshot(
            sleepRows: await readSleepRows(start: start, end: now),
            dailyRows: await readDailyRows(start: start, end: now),
            bodyRows: await readBodyRows(start: start, end: now)
        )
        // 日次集計の区間端など境界付近のサンプルを確実に落とすため、純粋関数側でもう一度フィルタする。
        return HealthCSVExportGenerator.filterByRetention(snapshot: snapshot, now: now)
        #else
        return HealthImportSnapshot()
        #endif
    }

    #if canImport(HealthKit)

    // MARK: - 睡眠

    private func readSleepRows(start: Date, end: Date) async -> [HealthSleepCSVRow] {
        guard let type = HKObjectType.categoryType(forIdentifier: .sleepAnalysis) else { return [] }
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])
        return await withCheckedContinuation { (continuation: CheckedContinuation<[HealthSleepCSVRow], Never>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                // HKSample はこのハンドラ内で Sendable な行に変換し、アクター境界を越えさせない。
                // 日ごとに合算せず、HealthKit から取れた区間のまま出す（ステージ推移を後で描くため）。
                let rows: [HealthSleepCSVRow] = (samples as? [HKCategorySample] ?? []).compactMap { sample in
                    guard let stage = HealthKitTypeMapping.sleepStage(forCategoryValue: sample.value) else {
                        return nil
                    }
                    return HealthSleepCSVRow(
                        start: sample.startDate,
                        end: sample.endDate,
                        stage: stage,
                        source: sample.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: rows)
            }
            store.execute(query)
        }
    }

    // MARK: - 日次サマリー

    private func readDailyRows(start: Date, end: Date) async -> [HealthDailyMetricCSVRow] {
        var rows: [HealthDailyMetricCSVRow] = []
        let ordered = HealthKitTypeMapping.dailyQuantityIdentifiers
            .sorted { $0.value.csvValue < $1.value.csvValue }
        for (identifier, metric) in ordered {
            rows.append(contentsOf: await readDailyRows(identifier: identifier, metric: metric, start: start, end: end))
        }
        return rows.sorted { lhs, rhs in
            if lhs.date != rhs.date { return lhs.date < rhs.date }
            if lhs.metric.csvValue != rhs.metric.csvValue { return lhs.metric.csvValue < rhs.metric.csvValue }
            return lhs.source < rhs.source
        }
    }

    private func readDailyRows(
        identifier: HKQuantityTypeIdentifier,
        metric: HealthDailyMetric,
        start: Date,
        end: Date
    ) async -> [HealthDailyMetricCSVRow] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }

        let anchor = Calendar.current.startOfDay(for: start)
        let unit = HealthKitTypeMapping.unit(for: metric)
        let averaged = HealthKitTypeMapping.isAveraged(metric)
        let options = HealthKitTypeMapping.statisticsOptions(for: metric)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])

        return await withCheckedContinuation { (continuation: CheckedContinuation<[HealthDailyMetricCSVRow], Never>) in
            let query = HKStatisticsCollectionQuery(
                quantityType: type,
                quantitySamplePredicate: predicate,
                options: options,
                anchorDate: anchor,
                intervalComponents: DateComponents(day: 1)
            )
            query.initialResultsHandler = { _, collection, _ in
                guard let collection else {
                    continuation.resume(returning: [])
                    return
                }
                var rows: [HealthDailyMetricCSVRow] = []
                collection.enumerateStatistics(from: anchor, to: end) { statistics, _ in
                    // 同じ date × metric に複数の source があれば、全ての source を行として出す。
                    // どれが正しいかは BodyOps 側では決めない（learning_coach 側で選ぶ）。
                    for source in statistics.sources ?? [] {
                        let quantity = averaged
                            ? statistics.averageQuantity(for: source)
                            : statistics.sumQuantity(for: source)
                        guard let quantity else { continue }
                        rows.append(
                            HealthDailyMetricCSVRow(
                                date: statistics.startDate,
                                metric: metric,
                                value: quantity.doubleValue(for: unit),
                                source: source.name
                            )
                        )
                    }
                }
                continuation.resume(returning: rows)
            }
            store.execute(query)
        }
    }

    // MARK: - 体組成

    private func readBodyRows(start: Date, end: Date) async -> [HealthBodyCSVRow] {
        var rows: [HealthBodyCSVRow] = []
        let ordered = HealthKitTypeMapping.bodyQuantityIdentifiers
            .sorted { $0.value.csvValue < $1.value.csvValue }
        for (identifier, metric) in ordered {
            rows.append(contentsOf: await readBodyRows(identifier: identifier, metric: metric, start: start, end: end))
        }
        return rows.sorted { lhs, rhs in
            if lhs.recordedAt != rhs.recordedAt { return lhs.recordedAt < rhs.recordedAt }
            if lhs.metric.csvValue != rhs.metric.csvValue { return lhs.metric.csvValue < rhs.metric.csvValue }
            return lhs.source < rhs.source
        }
    }

    private func readBodyRows(
        identifier: HKQuantityTypeIdentifier,
        metric: HealthBodyMetric,
        start: Date,
        end: Date
    ) async -> [HealthBodyCSVRow] {
        guard let type = HKObjectType.quantityType(forIdentifier: identifier) else { return [] }
        let unit = HealthKitTypeMapping.unit(for: metric)
        let scale = HealthKitTypeMapping.valueScale(for: metric)
        let predicate = HKQuery.predicateForSamples(withStart: start, end: end, options: [.strictStartDate])

        return await withCheckedContinuation { (continuation: CheckedContinuation<[HealthBodyCSVRow], Never>) in
            let query = HKSampleQuery(
                sampleType: type,
                predicate: predicate,
                limit: HKObjectQueryNoLimit,
                sortDescriptors: [NSSortDescriptor(key: HKSampleSortIdentifierStartDate, ascending: true)]
            ) { _, samples, _ in
                let rows: [HealthBodyCSVRow] = (samples as? [HKQuantitySample] ?? []).map { sample in
                    HealthBodyCSVRow(
                        recordedAt: sample.startDate,
                        metric: metric,
                        value: sample.quantity.doubleValue(for: unit) * scale,
                        source: sample.sourceRevision.source.name
                    )
                }
                continuation.resume(returning: rows)
            }
            store.execute(query)
        }
    }

    #endif
}
