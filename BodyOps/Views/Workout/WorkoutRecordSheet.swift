import SwiftUI
import SwiftData

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

struct WorkoutRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.date) private var allSessions: [WorkoutSession]
    let date: Date
    var editingSession: WorkoutSession? = nil

    @State private var exercises: [WorkoutExerciseEntry] = []
    @State private var sessionMemo = ""
    @State private var showExercisePicker = false
    @State private var copyDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var calendarMonth: Date = Calendar.current.startOfMonth(for: Date())

    private var isEditMode: Bool { editingSession != nil }

    var body: some View {
        NavigationStack {
            List {
                if !isEditMode {
                    copyLastSessionSection
                }
                ForEach($exercises) { $entry in
                    exerciseSection(entry: $entry)
                }
                addExerciseSection
                memoSection
            }
            .navigationTitle(isEditMode ? "記録を編集" : "筋トレ記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("保存") { saveSession() }
                        .disabled(exercises.isEmpty)
                }
            }
            .sheet(isPresented: $showExercisePicker) {
                ExercisePickerView { exercise in
                    addExercise(exercise)
                    showExercisePicker = false
                }
            }
            .onAppear {
                if let session = editingSession {
                    loadSession(session)
                }
            }
        }
    }

    // MARK: - Sections

    @ViewBuilder
    private var copyLastSessionSection: some View {
        Section("メニューをコピー") {
            copyCalendarView

            // その日の全セッションを集約（1日複数回に分けて保存した場合も全種目表示）
            let sessionsForDate = fetchSessions(for: copyDate)
            let allSets = sessionsForDate.flatMap { loadSets(for: $0) }
            let names = Array(Set(allSets.compactMap { $0.exercise?.name })).sorted()

            if names.isEmpty {
                Text("この日の記録はありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(names, id: \.self) { name in
                    Label(name, systemImage: "dumbbell.fill")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
                Button {
                    copySessions(sessionsForDate)
                } label: {
                    Label("このメニューをコピー", systemImage: "doc.on.doc")
                }
                .foregroundStyle(Color.accentColor)
            }
        }
    }

    // MARK: - Copy Calendar

    private var copyCalendarView: some View {
        VStack(spacing: 8) {
            // 月ヘッダー
            HStack {
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(copyCalendarMonthTitle)
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    let next = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth
                    if next <= Calendar.current.startOfMonth(for: Date()) {
                        calendarMonth = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // LazyVGrid は List 内で recursive layout loop を起こすため
            // VStack + HStack の明示的な行レイアウトを使用
            VStack(spacing: 4) {
                // 曜日ヘッダー行
                HStack(spacing: 0) {
                    ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { wd in
                        Text(wd)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                // 日付を7列の行に分割して描画
                let days = paddedCalendarDays
                let rowCount = days.count / 7
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7) { col in
                            let item = days[row * 7 + col]
                            Group {
                                if let day = item {
                                    copyDayCell(for: day)
                                } else {
                                    Color.clear.frame(height: 32)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func copyDayCell(for date: Date) -> some View {
        let hasSession = sessionDates.contains(Calendar.current.startOfDay(for: date))
        let isSelected = Calendar.current.isDate(date, inSameDayAs: copyDate)
        let isFuture = date > Date()
        return Button {
            if !isFuture {
                copyDate = Calendar.current.startOfDay(for: date)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 30, height: 30)
                VStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.caption)
                        .foregroundStyle(
                            isFuture ? Color.secondary.opacity(0.4)
                            : isSelected ? .white
                            : .primary
                        )
                    Circle()
                        .fill(
                            hasSession
                            ? (isSelected ? Color.white : Color.accentColor)
                            : Color.clear
                        )
                        .frame(width: 4, height: 4)
                }
            }
        }
        .disabled(isFuture)
        .buttonStyle(.plain)
    }

    private var copyCalendarDays: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: calendarMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: calendarMonth)
        let offset = (weekday - 2 + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: calendarMonth) {
                days.append(date)
            }
        }
        return days
    }

    /// VStack+HStack レイアウト用に7の倍数へパディングした配列
    private var paddedCalendarDays: [Date?] {
        var days = copyCalendarDays
        let remainder = days.count % 7
        if remainder != 0 {
            days += Array(repeating: nil, count: 7 - remainder)
        }
        return days
    }

    /// セッションが存在する日付（startOfDay）のセットをキャッシュ
    private var sessionDates: Set<Date> {
        Set(allSessions.map { Calendar.current.startOfDay(for: $0.date) })
    }

    private var copyCalendarMonthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: calendarMonth)
    }

    private var addExerciseSection: some View {
        Section {
            Button {
                showExercisePicker = true
            } label: {
                Label("種目を追加", systemImage: "plus.circle.fill")
            }
        }
    }

    private var memoSection: some View {
        Section("メモ") {
            TextField("セッションメモ（任意）", text: $sessionMemo, axis: .vertical)
                .lineLimit(3...)
        }
    }

    @ViewBuilder
    private func exerciseSection(entry: Binding<WorkoutExerciseEntry>) -> some View {
        let previousSets = fetchPreviousSets(for: entry.wrappedValue.exercise)
        Section {
            // 前回の記録サマリー + コピーボタン
            if !previousSets.isEmpty {
                HStack(alignment: .top, spacing: 8) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("前回の記録")
                            .font(.caption.bold())
                            .foregroundStyle(.secondary)
                        ForEach(previousSets, id: \.id) { set in
                            Text("Set\(set.setNumber):  \(Self.fmtWeight(set.weight))kg × \(set.reps)回")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                        }
                    }
                    Spacer()
                    Button("前回をコピー") {
                        entry.sets.wrappedValue = previousSets.enumerated().map { idx, s in
                            WorkoutSetEntry(setNumber: idx + 1, weight: s.weight, reps: s.reps)
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.bordered)
                }
                .padding(.vertical, 2)
            }

            ForEach(entry.sets.indices, id: \.self) { index in
                SetInputRow(
                    setNumber: entry.sets[index].wrappedValue.setNumber,
                    weight: entry.sets[index].wrappedValue.weight,
                    reps: entry.sets[index].wrappedValue.reps,
                    previousWeight: index < previousSets.count ? previousSets[index].weight : nil,
                    previousReps: index < previousSets.count ? previousSets[index].reps : nil,
                    onUpdate: { weight, reps in
                        entry.sets[index].wrappedValue.weight = weight
                        entry.sets[index].wrappedValue.reps = reps
                    }
                )
                .id(entry.sets[index].wrappedValue.id)
            }
            .onDelete { indexSet in
                entry.sets.wrappedValue.remove(atOffsets: indexSet)
                renumberSets(in: entry)
            }

            Button {
                addSet(to: entry)
            } label: {
                Label("+ セット追加", systemImage: "plus")
                    .font(.subheadline)
            }

            HStack {
                Text("合計ボリューム")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f kg", entry.wrappedValue.totalVolume))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if !isEditMode {
                Button {
                    saveExercise(entry.wrappedValue)
                } label: {
                    Label("この種目を保存", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(entry.wrappedValue.sets.isEmpty)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
            }
        } header: {
            HStack {
                Text(entry.wrappedValue.exercise.name)
                    .font(.subheadline.bold())
                Spacer()
                Text(entry.wrappedValue.exercise.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    private func addExercise(_ exercise: Exercise) {
        exercises.append(WorkoutExerciseEntry(exercise: exercise, sets: [
            WorkoutSetEntry(setNumber: 1, weight: 0, reps: 0)
        ]))
    }

    private func addSet(to entry: Binding<WorkoutExerciseEntry>) {
        let last = entry.wrappedValue.sets.last
        entry.sets.wrappedValue.append(WorkoutSetEntry(
            setNumber: entry.wrappedValue.sets.count + 1,
            weight: last?.weight ?? 0,
            reps: last?.reps ?? 0
        ))
    }

    private func renumberSets(in entry: Binding<WorkoutExerciseEntry>) {
        for index in entry.sets.wrappedValue.indices {
            entry.sets.wrappedValue[index].setNumber = index + 1
        }
    }

    private func loadSession(_ session: WorkoutSession) {
        sessionMemo = session.memo
        exercises.removeAll()

        var exerciseOrder: [UUID] = []
        var setsByExercise: [UUID: [WorkoutSet]] = [:]

        for set in loadSets(for: session) {
            guard let exerciseId = set.exercise?.id else { continue }
            if setsByExercise[exerciseId] == nil {
                setsByExercise[exerciseId] = []
                exerciseOrder.append(exerciseId)
            }
            setsByExercise[exerciseId]?.append(set)
        }

        for exerciseId in exerciseOrder {
            guard let sets = setsByExercise[exerciseId],
                  let exercise = sets.first?.exercise else { continue }
            let entries = sets.sorted { $0.setNumber < $1.setNumber }.enumerated().map { idx, set in
                WorkoutSetEntry(setNumber: idx + 1, weight: set.weight, reps: set.reps)
            }
            exercises.append(WorkoutExerciseEntry(exercise: exercise, sets: entries))
        }
    }

    private func saveExercise(_ entry: WorkoutExerciseEntry) {
        let session = WorkoutSession(date: date, memo: sessionMemo)
        var totalVolume = 0.0
        for setEntry in entry.sets {
            let workoutSet = WorkoutSet(
                setNumber: setEntry.setNumber,
                weight: setEntry.weight,
                reps: setEntry.reps,
                exercise: entry.exercise,
                session: session
            )
            totalVolume += setEntry.volume
            modelContext.insert(workoutSet)
        }
        session.totalVolume = totalVolume
        modelContext.insert(session)
        try? modelContext.save()
        exercises.removeAll { $0.id == entry.id }
        if exercises.isEmpty { dismiss() }
    }

    private func saveSession() {
        if let session = editingSession {
            // 編集モード: 既存のセットを削除して再作成
            for set in loadSets(for: session) { modelContext.delete(set) }
            session.memo = sessionMemo
            var totalVolume = 0.0
            for entry in exercises {
                for setEntry in entry.sets {
                    let workoutSet = WorkoutSet(
                        setNumber: setEntry.setNumber,
                        weight: setEntry.weight,
                        reps: setEntry.reps,
                        exercise: entry.exercise,
                        session: session
                    )
                    totalVolume += setEntry.volume
                    modelContext.insert(workoutSet)
                }
            }
            session.totalVolume = totalVolume
        } else {
            // 新規作成
            let session = WorkoutSession(date: date, memo: sessionMemo)
            var totalVolume = 0.0
            for entry in exercises {
                for setEntry in entry.sets {
                    let workoutSet = WorkoutSet(
                        setNumber: setEntry.setNumber,
                        weight: setEntry.weight,
                        reps: setEntry.reps,
                        exercise: entry.exercise,
                        session: session
                    )
                    totalVolume += setEntry.volume
                    modelContext.insert(workoutSet)
                }
            }
            session.totalVolume = totalVolume
            modelContext.insert(session)
        }
        try? modelContext.save()
        dismiss()
    }

    // MARK: - Fetch Helpers

    private static func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }

    /// 指定日の全セッションを返す（1日複数セッション対応）
    private func fetchSessions(for date: Date) -> [WorkoutSession] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        let descriptor = FetchDescriptor<WorkoutSession>(
            predicate: #Predicate { $0.date >= start && $0.date < end },
            sortBy: [SortDescriptor(\.date)]
        )
        return (try? modelContext.fetch(descriptor)) ?? []
    }

    private func fetchPreviousSets(for exercise: Exercise) -> [WorkoutSet] {
        let exerciseId = exercise.id
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exercise?.id == exerciseId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allSets = (try? modelContext.fetch(descriptor)) ?? []
        guard let lastSession = allSets.first?.session else { return [] }
        let lastSessionId = lastSession.id
        return allSets.filter { $0.session?.id == lastSessionId }
            .sorted { $0.setNumber < $1.setNumber }
    }

    /// セッションに紐づく全セットをメモリフィルターで確実に取得する
    /// （predicate の optional chaining や session.sets のレイジーロードに依存しない）
    private func loadSets(for session: WorkoutSession) -> [WorkoutSet] {
        let sessionId = session.id
        let all = (try? modelContext.fetch(FetchDescriptor<WorkoutSet>())) ?? []
        let filtered = all
            .filter { $0.session?.id == sessionId }
            .sorted { $0.setNumber < $1.setNumber }
        return filtered.isEmpty
            ? session.sets.sorted { $0.setNumber < $1.setNumber }
            : filtered
    }

    /// 指定日の全セッションから種目・セットをまとめてコピーする
    private func copySessions(_ sessions: [WorkoutSession]) {
        exercises.removeAll()
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
        for exerciseId in exerciseOrder {
            guard let sets = setsByExercise[exerciseId],
                  let exercise = sets.first?.exercise else { continue }
            let entries = sets.sorted { $0.setNumber < $1.setNumber }.enumerated().map { idx, set in
                WorkoutSetEntry(setNumber: idx + 1, weight: set.weight, reps: set.reps)
            }
            exercises.append(WorkoutExerciseEntry(exercise: exercise, sets: entries))
        }
    }
}

// MARK: - SetInputRow

struct SetInputRow: View {
    let setNumber: Int
    let previousWeight: Double?
    let previousReps: Int?
    let onUpdate: (Double, Int) -> Void

    @State private var weight: Double
    @State private var reps: Int
    @State private var weightText: String
    @State private var repsText: String

    init(setNumber: Int, weight: Double, reps: Int,
         previousWeight: Double?, previousReps: Int?,
         onUpdate: @escaping (Double, Int) -> Void) {
        self.setNumber = setNumber
        self._weight = State(initialValue: weight)
        self._reps = State(initialValue: reps)
        self._weightText = State(initialValue: weight > 0 ? Self.fmtWeight(weight) : "")
        self._repsText = State(initialValue: reps > 0 ? "\(reps)" : "")
        self.previousWeight = previousWeight
        self.previousReps = previousReps
        self.onUpdate = onUpdate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Set \(setNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                Spacer()

                // 重量
                HStack(spacing: 6) {
                    stepButton("minus") { stepWeight(-1) }
                    VStack(spacing: 1) {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 52)
                            .onChange(of: weightText) { _, t in
                                if let v = Double(t) {
                                    weight = max(0, v)
                                    onUpdate(weight, reps)
                                }
                            }
                        Text("kg").font(.caption2).foregroundStyle(.secondary)
                    }
                    stepButton("plus") { stepWeight(1) }
                }

                Spacer()

                // レップ数
                HStack(spacing: 6) {
                    stepButton("minus") { stepReps(-1) }
                    VStack(spacing: 1) {
                        TextField("0", text: $repsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 36)
                            .onChange(of: repsText) { _, t in
                                if let v = Int(t) {
                                    reps = max(0, v)
                                    onUpdate(weight, reps)
                                }
                            }
                        Text("回").font(.caption2).foregroundStyle(.secondary)
                    }
                    stepButton("plus") { stepReps(1) }
                }
            }

            if let prevW = previousWeight, let prevR = previousReps {
                Text("前回: \(Self.fmtWeight(prevW))kg × \(prevR)回")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Color(.systemGray5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func stepWeight(_ delta: Double) {
        weight = max(0, weight + delta)
        weightText = Self.fmtWeight(weight)
        onUpdate(weight, reps)
    }

    private func stepReps(_ delta: Int) {
        reps = max(0, reps + delta)
        repsText = "\(reps)"
        onUpdate(weight, reps)
    }

    private static func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}
