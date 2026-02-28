import Foundation
import SwiftData

// MARK: - Parsed Models

struct CSVWorkoutSession {
    let date: Date
    let memo: String
    let exercises: [CSVExerciseEntry]

    var totalSets: Int { exercises.reduce(0) { $0 + $1.sets.count } }
}

struct CSVExerciseEntry {
    let name: String
    let sets: [CSVSetEntry]
}

struct CSVSetEntry {
    let setNumber: Int
    let weightKg: Double
    let reps: Int
}

// MARK: - Importer

struct WorkoutCSVImporter {

    enum ImportError: LocalizedError {
        case emptyFile
        case invalidHeader
        case parseError(line: Int, detail: String)

        var errorDescription: String? {
            switch self {
            case .emptyFile:
                return "CSVファイルが空です"
            case .invalidHeader:
                return "ヘッダー行が不正です。date,exercise_name,set_number,weight_kg,reps,session_memo が必要です"
            case .parseError(let line, let detail):
                return "\(line)行目のパースエラー: \(detail)"
            }
        }
    }

    /// CSVテキストをパースしてCSVWorkoutSession配列を返す
    static func parse(csvText: String) throws -> [CSVWorkoutSession] {
        let lines = csvText
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }

        guard !lines.isEmpty else { throw ImportError.emptyFile }

        // ヘッダー検証
        let header = lines[0].lowercased()
        guard header.contains("date") && header.contains("exercise_name")
                && header.contains("weight_kg") && header.contains("reps") else {
            throw ImportError.invalidHeader
        }

        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        struct CSVRow {
            let exerciseName: String
            let setNumber: Int
            let weightKg: Double
            let reps: Int
            let memo: String
        }

        // date → [CSVRow]
        var rowsByDate: [String: [CSVRow]] = [:]
        var dateOrder: [String] = []

        for (index, line) in lines.dropFirst().enumerated() {
            let lineNumber = index + 2
            let cols = line.components(separatedBy: ",")
            guard cols.count >= 5 else {
                throw ImportError.parseError(line: lineNumber, detail: "列数が不足しています（最低5列必要）")
            }
            let dateStr = cols[0].trimmingCharacters(in: .whitespaces)
            let exerciseName = cols[1].trimmingCharacters(in: .whitespaces)
            let memo = cols.count >= 6 ? cols[5].trimmingCharacters(in: .whitespaces) : ""

            guard !dateStr.isEmpty else {
                throw ImportError.parseError(line: lineNumber, detail: "日付が空です")
            }
            guard dateFormatter.date(from: dateStr) != nil else {
                throw ImportError.parseError(line: lineNumber, detail: "日付フォーマットが不正です（YYYY-MM-DD）: \(dateStr)")
            }
            guard !exerciseName.isEmpty else {
                throw ImportError.parseError(line: lineNumber, detail: "種目名が空です")
            }
            guard let setNumber = Int(cols[2].trimmingCharacters(in: .whitespaces)) else {
                throw ImportError.parseError(line: lineNumber, detail: "set_numberが整数ではありません")
            }
            guard let weight = Double(cols[3].trimmingCharacters(in: .whitespaces)) else {
                throw ImportError.parseError(line: lineNumber, detail: "weight_kgが数値ではありません")
            }
            guard let reps = Int(cols[4].trimmingCharacters(in: .whitespaces)) else {
                throw ImportError.parseError(line: lineNumber, detail: "repsが整数ではありません")
            }

            if rowsByDate[dateStr] == nil {
                rowsByDate[dateStr] = []
                dateOrder.append(dateStr)
            }
            rowsByDate[dateStr]?.append(CSVRow(
                exerciseName: exerciseName,
                setNumber: setNumber,
                weightKg: weight,
                reps: reps,
                memo: memo
            ))
        }

        // dateOrder順にCSVWorkoutSessionを組み立て
        var sessions: [CSVWorkoutSession] = []
        for dateStr in dateOrder {
            guard let rows = rowsByDate[dateStr],
                  let date = dateFormatter.date(from: dateStr) else { continue }

            // session_memo: そのdateで最初の非空値
            let sessionMemo = rows.first(where: { !$0.memo.isEmpty })?.memo ?? ""

            // 種目ごとにグループ化（順序保持）
            var exerciseOrder: [String] = []
            var setsByExercise: [String: [CSVSetEntry]] = [:]
            for row in rows {
                if setsByExercise[row.exerciseName] == nil {
                    setsByExercise[row.exerciseName] = []
                    exerciseOrder.append(row.exerciseName)
                }
                setsByExercise[row.exerciseName]?.append(
                    CSVSetEntry(setNumber: row.setNumber, weightKg: row.weightKg, reps: row.reps)
                )
            }

            let exercises = exerciseOrder.compactMap { name -> CSVExerciseEntry? in
                guard let sets = setsByExercise[name] else { return nil }
                return CSVExerciseEntry(name: name, sets: sets.sorted { $0.setNumber < $1.setNumber })
            }

            sessions.append(CSVWorkoutSession(date: date, memo: sessionMemo, exercises: exercises))
        }

        return sessions
    }

    /// パース済みセッションをSwiftDataに保存する。既存の同日セッションはスキップ。
    @MainActor
    static func save(sessions: [CSVWorkoutSession], context: ModelContext) -> (imported: Int, skipped: Int) {
        var imported = 0
        var skipped = 0

        for csvSession in sessions {
            let start = Calendar.current.startOfDay(for: csvSession.date)
            let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start

            // 重複チェック
            let existsDescriptor = FetchDescriptor<WorkoutSession>(
                predicate: #Predicate { $0.date >= start && $0.date < end }
            )
            if let existing = try? context.fetch(existsDescriptor), !existing.isEmpty {
                skipped += 1
                continue
            }

            let session = WorkoutSession(date: csvSession.date, memo: csvSession.memo)
            var totalVolume = 0.0

            for csvExercise in csvSession.exercises {
                // 既存種目を検索 or 新規作成
                let exerciseName = csvExercise.name
                let exerciseDescriptor = FetchDescriptor<Exercise>(
                    predicate: #Predicate { $0.name == exerciseName }
                )
                let exercise: Exercise
                if let found = try? context.fetch(exerciseDescriptor).first {
                    exercise = found
                } else {
                    exercise = Exercise(name: exerciseName, category: "その他", isPreset: false)
                    context.insert(exercise)
                }

                for csvSet in csvExercise.sets {
                    let workoutSet = WorkoutSet(
                        setNumber: csvSet.setNumber,
                        weight: csvSet.weightKg,
                        reps: csvSet.reps,
                        exercise: exercise,
                        session: session
                    )
                    totalVolume += csvSet.weightKg * Double(csvSet.reps)
                    context.insert(workoutSet)
                }
            }

            session.totalVolume = totalVolume
            context.insert(session)
            imported += 1
        }

        try? context.save()
        return (imported, skipped)
    }
}
