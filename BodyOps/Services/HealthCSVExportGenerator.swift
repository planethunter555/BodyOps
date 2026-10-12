import Foundation

/// Apple ヘルスケア（HealthKit）由来データのCSV生成。
/// HealthKit・SwiftData・iCloud・ネットワークに一切依存しない純粋関数のみで構成し、
/// 単体テストだけで挙動を検証できるようにする（HealthKit本体は実機/シミュレータでないと動かないため）。
enum HealthCSVExportGenerator {
    static let sleepHeader = "start,end,stage,source"
    static let dailyHeader = "date,metric,value,unit,source"
    static let bodyHeader = "recorded_at,metric,value,unit,source"

    /// CSVに出す取得期間（直近N日）。ファイルが無限に育つのを防ぐ。
    static let retentionDays = 365

    // MARK: - CSV

    static func sleepCSV(rows: [HealthSleepCSVRow], timeZone: TimeZone = .current) -> String {
        let formatter = makeISO8601Formatter(timeZone: timeZone)
        var lines = [sleepHeader]
        for row in rows {
            lines.append([
                formatter.string(from: row.start),
                formatter.string(from: row.end),
                escape(row.stage.csvValue),
                escape(row.source)
            ].joined(separator: ","))
        }
        return join(lines)
    }

    static func dailyCSV(rows: [HealthDailyMetricCSVRow], timeZone: TimeZone = .current) -> String {
        let formatter = makeDayFormatter(timeZone: timeZone)
        var lines = [dailyHeader]
        for row in rows {
            lines.append([
                formatter.string(from: row.date),
                escape(row.metric.csvValue),
                formatValue(row.value),
                escape(row.metric.unit),
                escape(row.source)
            ].joined(separator: ","))
        }
        return join(lines)
    }

    static func bodyCSV(rows: [HealthBodyCSVRow], timeZone: TimeZone = .current) -> String {
        let formatter = makeISO8601Formatter(timeZone: timeZone)
        var lines = [bodyHeader]
        for row in rows {
            lines.append([
                formatter.string(from: row.recordedAt),
                escape(row.metric.csvValue),
                formatValue(row.value),
                escape(row.metric.unit),
                escape(row.source)
            ].joined(separator: ","))
        }
        return join(lines)
    }

    // MARK: - 保持期間フィルタ

    /// 直近 `retentionDays` 日より古いサンプルを除外する基準日時
    static func retentionStartDate(now: Date, days: Int = retentionDays) -> Date {
        now.addingTimeInterval(-Double(days) * 86_400)
    }

    static func filterByRetention(
        snapshot: HealthImportSnapshot,
        now: Date,
        days: Int = retentionDays
    ) -> HealthImportSnapshot {
        let cutoff = retentionStartDate(now: now, days: days)
        return HealthImportSnapshot(
            sleepRows: snapshot.sleepRows.filter { $0.start >= cutoff },
            dailyRows: snapshot.dailyRows.filter { $0.date >= cutoff },
            bodyRows: snapshot.bodyRows.filter { $0.recordedAt >= cutoff }
        )
    }

    // MARK: - Private

    private static func join(_ lines: [String]) -> String {
        lines.map { $0 + "\r\n" }.joined()
    }

    /// ISO8601（タイムゾーンオフセット付き。例 `2026-10-12T23:10:00+09:00`）。
    /// `XXXXX` はUTCのとき `Z`、それ以外は `+09:00` 形式のコロン付きオフセットになる。
    private static func makeISO8601Formatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd'T'HH:mm:ssXXXXX"
        return formatter
    }

    private static func makeDayFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }

    /// 数値の文字列化。整数なら小数点なし、小数があれば末尾のゼロを落として最大4桁まで出す。
    /// （歩数が `12345.0` ではなく `12345` になるように）
    static func formatValue(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        if value == value.rounded() && abs(value) < 1e15 {
            return String(Int(value))
        }
        var text = String(format: "%.4f", value)
        while text.hasSuffix("0") { text.removeLast() }
        if text.hasSuffix(".") { text.removeLast() }
        return text
    }

    /// RFC4180準拠のエスケープ。カンマ・ダブルクォート・改行を含む場合のみダブルクォートで囲む。
    /// （HealthKitの `HKSource.name` はユーザーが入れたアプリ名なのでカンマや引用符を含みうる）
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
