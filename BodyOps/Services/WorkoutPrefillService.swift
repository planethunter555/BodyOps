import Foundation
import SwiftData

/// 筋トレ記録シートの入力エントリ（保存前のインメモリ表現）
struct WorkoutSetEntry: Identifiable {
    let id = UUID()
    var setNumber: Int
    var weight: Double
    var reps: Int
    var volume: Double { weight * Double(reps) }
}

struct WorkoutExerciseEntry: Identifiable {
    let id = UUID()
    var exercise: Exercise
    var sets: [WorkoutSetEntry]
    var totalVolume: Double { sets.reduce(0) { $0 + $1.volume } }
}

/// 過去の記録から入力値をプリフィルするロジックを集約したサービス。
/// WorkoutRecordSheet / CopyFromDateSheet から利用する。
struct WorkoutPrefillService {
    let context: ModelContext

    /// 指定日の全セッションを返す（1日複数セッション対応）
    func sessions(for date: Date) -> [WorkoutSession] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// 指定種目の直近セッションのセット（setNumber昇順）
    func previousSets(for exercise: Exercise) -> [WorkoutSet] {
        let exerciseId = exercise.id
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exercise?.id == exerciseId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allSets = (try? context.fetch(descriptor)) ?? []
        guard let lastSession = allSets.first?.session else { return [] }
        let lastSessionId = lastSession.id
        return allSets.filter { $0.session?.id == lastSessionId }
            .sorted { $0.setNumber < $1.setNumber }
    }

    /// 指定種目の直近セットを入力エントリとして返す（プリフィル用）
    func latestEntries(for exercise: Exercise) -> [WorkoutSetEntry] {
        previousSets(for: exercise).enumerated().map { idx, set in
            WorkoutSetEntry(setNumber: idx + 1, weight: set.weight, reps: set.reps)
        }
    }

    /// 指定日の全セッションから種目・セットを入力エントリとして返す（日付コピー用）。
    /// 種目の登場順を保持する。
    func entries(for date: Date) -> [WorkoutExerciseEntry] {
        entries(from: sessions(for: date))
    }

    /// セッション群を種目ごとにグルーピングして入力エントリ化する
    func entries(from sessions: [WorkoutSession]) -> [WorkoutExerciseEntry] {
        var exerciseOrder: [UUID] = []
        var setsByExercise: [UUID: [WorkoutSet]] = [:]
        for set in sessions.flatMap({ loadSets(for: $0) }) {
            guard let exerciseId = set.exercise?.id else { continue }
            if setsByExercise[exerciseId] == nil {
                setsByExercise[exerciseId] = []
                exerciseOrder.append(exerciseId)
            }
            setsByExercise[exerciseId]?.append(set)
        }
        var result: [WorkoutExerciseEntry] = []
        for exerciseId in exerciseOrder {
            guard let sets = setsByExercise[exerciseId],
                  let exercise = sets.first?.exercise else { continue }
            let entries = sets.sorted { $0.setNumber < $1.setNumber }.enumerated().map { idx, set in
                WorkoutSetEntry(setNumber: idx + 1, weight: set.weight, reps: set.reps)
            }
            result.append(WorkoutExerciseEntry(exercise: exercise, sets: entries))
        }
        return result
    }

    /// 指定日より前で最も新しいセッションの日付（「前回のトレーニングをコピー」用）
    func mostRecentSessionDate(before date: Date) -> Date? {
        let dayStart = Calendar.current.startOfDay(for: date)
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date < dayStart },
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        var limited = descriptor
        limited.fetchLimit = 1
        return (try? context.fetch(limited))?.first?.date
    }

    /// セッションに紐づく全セットをメモリフィルターで確実に取得する
    /// （predicate の optional chaining や session.sets のレイジーロードに依存しない）
    func loadSets(for session: WorkoutSession) -> [WorkoutSet] {
        let sessionId = session.id
        let all = (try? context.fetch(FetchDescriptor<WorkoutSet>())) ?? []
        let filtered = all
            .filter { $0.session?.id == sessionId }
            .sorted { $0.setNumber < $1.setNumber }
        return filtered.isEmpty
            ? session.sets.sorted { $0.setNumber < $1.setNumber }
            : filtered
    }
}
