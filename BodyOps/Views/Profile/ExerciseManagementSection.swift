import SwiftUI
import SwiftData

/// 設定画面のカスタム種目管理セクション（自己完結）
struct ExerciseManagementSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query(filter: #Predicate<Exercise> { !$0.isPreset }, sort: \Exercise.name)
    private var customExercises: [Exercise]

    var body: some View {
        Section("カスタム種目") {
            if customExercises.isEmpty {
                Text("カスタム種目はありません")
                    .foregroundStyle(.secondary)
                    .font(.subheadline)
            } else {
                ForEach(customExercises) { exercise in
                    HStack {
                        Text(exercise.name)
                        Spacer()
                        Text(exercise.category)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete { indexSet in
                    deleteCustomExercises(at: indexSet)
                }
            }
        }
    }

    private func deleteCustomExercises(at indexSet: IndexSet) {
        for index in indexSet {
            modelContext.delete(customExercises[index])
        }
        try? modelContext.save()
    }
}
