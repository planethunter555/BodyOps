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
    let date: Date

    @State private var exercises: [WorkoutExerciseEntry] = []
    @State private var sessionMemo = ""
    @State private var showExercisePicker = false

    var body: some View {
        NavigationStack {
            List {
                copyLastSessionSection
                ForEach($exercises) { $entry in
                    exerciseSection(entry: $entry)
                }
                addExerciseSection
                memoSection
            }
            .navigationTitle("筋トレ記録")
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
        }
    }

    @ViewBuilder
    private var copyLastSessionSection: some View {
        let lastSession = fetchLastSession()
        Section {
            Button {
                if let session = lastSession {
                    copySession(session)
                }
            } label: {
                Label("前回と同じメニューをコピー", systemImage: "doc.on.doc")
            }
            .disabled(lastSession == nil)
            .foregroundStyle(lastSession == nil ? Color.secondary : Color.accentColor)
        }
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
            ForEach(entry.sets.indices, id: \.self) { index in
                setRow(
                    setEntry: entry.sets[index].wrappedValue,
                    setIndex: index,
                    previousSet: index < previousSets.count ? previousSets[index] : nil,
                    onUpdate: { weight, reps in
                        entry.sets[index].wrappedValue.weight = weight
                        entry.sets[index].wrappedValue.reps = reps
                    }
                )
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

    private func setRow(
        setEntry: WorkoutSetEntry,
        setIndex: Int,
        previousSet: WorkoutSet?,
        onUpdate: @escaping (Double, Int) -> Void
    ) -> some View {
        SetInputRow(
            setNumber: setEntry.setNumber,
            weight: setEntry.weight,
            reps: setEntry.reps,
            previousWeight: previousSet?.weight,
            previousReps: previousSet?.reps,
            onUpdate: onUpdate
        )
    }

    private func addExercise(_ exercise: Exercise) {
        let entry = WorkoutExerciseEntry(exercise: exercise, sets: [
            WorkoutSetEntry(setNumber: 1, weight: 0, reps: 0)
        ])
        exercises.append(entry)
    }

    private func addSet(to entry: Binding<WorkoutExerciseEntry>) {
        let currentSets = entry.wrappedValue.sets
        let lastSet = currentSets.last
        let newSet = WorkoutSetEntry(
            setNumber: currentSets.count + 1,
            weight: lastSet?.weight ?? 0,
            reps: lastSet?.reps ?? 0
        )
        entry.sets.wrappedValue.append(newSet)
    }

    private func renumberSets(in entry: Binding<WorkoutExerciseEntry>) {
        for index in entry.sets.wrappedValue.indices {
            entry.sets.wrappedValue[index].setNumber = index + 1
        }
    }

    private func fetchPreviousSets(for exercise: Exercise) -> [WorkoutSet] {
        let exerciseId = exercise.id
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.exercise?.id == exerciseId },
            sortBy: [SortDescriptor(\.createdAt, order: .reverse)]
        )
        let allSets = (try? modelContext.fetch(descriptor)) ?? []
        guard let lastSessionSet = allSets.first,
              let lastSession = lastSessionSet.session else {
            return []
        }
        let lastSessionId = lastSession.id
        return allSets.filter { $0.session?.id == lastSessionId }
            .sorted { $0.setNumber < $1.setNumber }
    }

    private func fetchLastSession() -> WorkoutSession? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        return try? modelContext.fetch(descriptor).first
    }

    private func copySession(_ session: WorkoutSession) {
        exercises.removeAll()
        let groupedSets = Dictionary(grouping: session.sets) { $0.exercise?.id }
        for (_, sets) in groupedSets {
            guard let exercise = sets.first?.exercise else { continue }
            let sortedSets = sets.sorted { $0.setNumber < $1.setNumber }
            let entries = sortedSets.enumerated().map { idx, set in
                WorkoutSetEntry(setNumber: idx + 1, weight: set.weight, reps: set.reps)
            }
            exercises.append(WorkoutExerciseEntry(exercise: exercise, sets: entries))
        }
    }

    private func saveSession() {
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
        try? modelContext.save()
        dismiss()
    }
}

struct SetInputRow: View {
    let setNumber: Int
    @State var weight: Double
    @State var reps: Int
    let previousWeight: Double?
    let previousReps: Int?
    let onUpdate: (Double, Int) -> Void

    var body: some View {
        HStack(spacing: 12) {
            Text("Set \(setNumber)")
                .font(.caption.bold())
                .foregroundStyle(.secondary)
                .frame(width: 40)

            Stepper(value: $weight, in: 0...500, step: 0.5) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.1f kg", weight))
                        .font(.subheadline)
                    if let prev = previousWeight, weight == 0 {
                        Text(String(format: "前回: %.1f kg", prev))
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onChange(of: weight) { _, newVal in onUpdate(newVal, reps) }

            Stepper(value: $reps, in: 0...100) {
                VStack(alignment: .leading, spacing: 2) {
                    Text("\(reps) 回")
                        .font(.subheadline)
                    if let prev = previousReps, reps == 0 {
                        Text("前回: \(prev)回")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            .onChange(of: reps) { _, newVal in onUpdate(weight, newVal) }

            Text(String(format: "%.0f", weight * Double(reps)))
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 40, alignment: .trailing)
        }
    }
}
