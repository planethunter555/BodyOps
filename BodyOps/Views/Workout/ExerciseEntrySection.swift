import SwiftUI

/// 筋トレ記録シート内の1種目分のセクション。
/// 前回記録の表示・コピー、セット行の編集・追加・削除、種目単位の保存を担う。
struct ExerciseEntrySection: View {
    @Binding var entry: WorkoutExerciseEntry
    let previousSets: [WorkoutSet]
    /// 前回の記録から自動入力された直後か（調整を促すキャプション表示用）
    let showsPrefilledHint: Bool
    let isEditMode: Bool
    let onSaveExercise: () -> Void

    var body: some View {
        Section {
            if showsPrefilledHint {
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
                        entry.sets = previousSets.enumerated().map { idx, s in
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
                    setNumber: entry.sets[index].setNumber,
                    weight: entry.sets[index].weight,
                    reps: entry.sets[index].reps,
                    previousWeight: index < previousSets.count ? previousSets[index].weight : nil,
                    previousReps: index < previousSets.count ? previousSets[index].reps : nil,
                    onUpdate: { weight, reps in
                        entry.sets[index].weight = weight
                        entry.sets[index].reps = reps
                    }
                )
                .id(entry.sets[index].id)
            }
            .onDelete { indexSet in
                entry.sets.remove(atOffsets: indexSet)
                renumberSets()
            }

            Button {
                addSet()
            } label: {
                Label("+ セット追加", systemImage: "plus")
                    .font(.subheadline)
            }

            HStack {
                Text("合計ボリューム")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Text(String(format: "%.0f kg", entry.totalVolume))
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
            }

            if !isEditMode {
                Button {
                    onSaveExercise()
                } label: {
                    Label("この種目を保存", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .disabled(entry.sets.isEmpty)
                .buttonStyle(.borderedProminent)
                .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 8, trailing: 16))
            }
        } header: {
            HStack {
                Text(entry.exercise.name)
                    .font(.subheadline.bold())
                Spacer()
                Text(entry.exercise.category)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Private

    private func addSet() {
        let last = entry.sets.last
        entry.sets.append(WorkoutSetEntry(
            setNumber: entry.sets.count + 1,
            weight: last?.weight ?? 0,
            reps: last?.reps ?? 0
        ))
    }

    private func renumberSets() {
        for index in entry.sets.indices {
            entry.sets[index].setNumber = index + 1
        }
    }

    private static func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}
