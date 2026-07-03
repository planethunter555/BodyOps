import SwiftUI
import SwiftData

struct WorkoutRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let date: Date
    var editingSession: WorkoutSession? = nil

    @State private var exercises: [WorkoutExerciseEntry] = []
    @State private var sessionMemo = ""
    @State private var showExercisePicker = false
    @State private var showCopyFromDateSheet = false
    /// 前回の記録から自動入力されたエントリのID（調整を促すキャプション表示用）
    @State private var prefilledEntryIds: Set<UUID> = []

    private var isEditMode: Bool { editingSession != nil }

    private var prefillService: WorkoutPrefillService {
        WorkoutPrefillService(context: modelContext)
    }

    var body: some View {
        NavigationStack {
            Group {
                if !isEditMode && exercises.isEmpty {
                    WorkoutEntryStartView(
                        lastSessionDate: prefillService.mostRecentSessionDate(before: date),
                        onCopyLastSession: copyLastSession,
                        onPickExercise: { showExercisePicker = true },
                        onCopyFromDate: { showCopyFromDateSheet = true }
                    )
                } else {
                    List {
                        ForEach($exercises) { $entry in
                            exerciseSection(entry: $entry)
                        }
                        addExerciseSection
                        memoSection
                    }
                }
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
            .sheet(isPresented: $showCopyFromDateSheet) {
                CopyFromDateSheet { entries in
                    exercises = entries
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
        let previousSets = prefillService.previousSets(for: entry.wrappedValue.exercise)
        Section {
            if prefilledEntryIds.contains(entry.wrappedValue.id) {
                Label("前回の記録を自動入力しました。数値を調整してください", systemImage: "wand.and.stars")
                    .font(.caption)
                    .foregroundStyle(Color.accentColor)
            }

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

    /// 種目を追加する。前回の記録があればセット内容を自動入力する。
    private func addExercise(_ exercise: Exercise) {
        let prefilled = prefillService.latestEntries(for: exercise)
        if prefilled.isEmpty {
            exercises.append(WorkoutExerciseEntry(exercise: exercise, sets: [
                WorkoutSetEntry(setNumber: 1, weight: 0, reps: 0)
            ]))
        } else {
            let entry = WorkoutExerciseEntry(exercise: exercise, sets: prefilled)
            exercises.append(entry)
            prefilledEntryIds.insert(entry.id)
        }
    }

    /// 直近のトレーニング日のメニュー全体を読み込む
    private func copyLastSession() {
        guard let lastDate = prefillService.mostRecentSessionDate(before: date) else { return }
        exercises = prefillService.entries(for: lastDate)
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
        exercises = prefillService.entries(from: [session])
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
            for set in prefillService.loadSets(for: session) { modelContext.delete(set) }
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

    private static func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
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
