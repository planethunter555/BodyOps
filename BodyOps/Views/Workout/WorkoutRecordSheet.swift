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
                        onLoadEntries: { entries in exercises = entries },
                        onPickExercise: { showExercisePicker = true }
                    )
                } else {
                    List {
                        ForEach($exercises) { $entry in
                            ExerciseEntrySection(
                                entry: $entry,
                                previousSets: prefillService.previousSets(for: entry.exercise),
                                showsPrefilledHint: prefilledEntryIds.contains(entry.id),
                                isEditMode: isEditMode,
                                onSaveExercise: { saveExercise(entry) }
                            )
                        }
                        addExerciseSection
                        memoSection
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .keyboardDoneButton()
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

}
