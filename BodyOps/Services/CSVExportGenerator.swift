import Foundation

/// iCloud書き出し用のCSV生成。SwiftData/iCloud/ネットワークに一切依存しない純粋関数のみで構成し、
/// 単体テストだけで挙動を検証できるようにする。
enum CSVExportGenerator {
    static let workoutsHeader = "session_id,session_date,exercise_name,category,set_number,weight_kg,reps,volume,memo"
    static let mealsHeader = "meal_id,recorded_at,meal_type,description,calories_kcal,protein_g,fat_g,carbs_g"

    static func workoutsCSV(sessions: [WorkoutSession]) -> String {
        workoutsCSV(rows: workoutRows(from: sessions))
    }

    static func mealsCSV(records: [MealRecord]) -> String {
        mealsCSV(rows: mealRows(from: records))
    }

    static func workoutRows(from sessions: [WorkoutSession]) -> [WorkoutSetCSVRow] {
        sessions.flatMap { session in
            session.sets.sorted { $0.setNumber < $1.setNumber }.map { set in
                WorkoutSetCSVRow(
                    sessionId: session.id,
                    sessionDate: session.date,
                    exerciseName: set.exercise?.name ?? "",
                    category: set.exercise?.category ?? "",
                    setNumber: set.setNumber,
                    weightKg: set.weight,
                    reps: set.reps,
                    volume: set.volume,
                    memo: session.memo
                )
            }
        }
    }

    static func mealRows(from records: [MealRecord]) -> [MealRecordCSVRow] {
        records.map { meal in
            MealRecordCSVRow(
                mealId: meal.id,
                recordedAt: meal.recordedAt,
                mealType: meal.mealType,
                mealDescription: meal.mealDescription,
                calories: meal.calories,
                protein: meal.protein,
                fat: meal.fat,
                carbs: meal.carbs
            )
        }
    }

    static func workoutsCSV(rows: [WorkoutSetCSVRow]) -> String {
        let formatter = makeDateFormatter()
        var lines = [workoutsHeader]
        for row in rows {
            let fields = [
                row.sessionId.uuidString,
                formatter.string(from: row.sessionDate),
                escape(row.exerciseName),
                escape(row.category),
                String(row.setNumber),
                String(row.weightKg),
                String(row.reps),
                String(row.volume),
                escape(row.memo)
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.map { $0 + "\r\n" }.joined()
    }

    static func mealsCSV(rows: [MealRecordCSVRow]) -> String {
        let formatter = makeDateFormatter()
        var lines = [mealsHeader]
        for row in rows {
            let fields = [
                row.mealId.uuidString,
                formatter.string(from: row.recordedAt),
                escape(row.mealType),
                escape(row.mealDescription),
                String(row.calories),
                String(row.protein),
                String(row.fat),
                String(row.carbs)
            ]
            lines.append(fields.joined(separator: ","))
        }
        return lines.map { $0 + "\r\n" }.joined()
    }

    // MARK: - Private

    private static func makeDateFormatter() -> DateFormatter {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter
    }

    /// RFC4180準拠のエスケープ。カンマ・ダブルクォート・改行を含む場合のみダブルクォートで囲む。
    private static func escape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") || field.contains("\r") else {
            return field
        }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }
}
