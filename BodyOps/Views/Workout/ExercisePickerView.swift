import SwiftUI
import SwiftData

struct ExercisePickerView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Query(sort: \Exercise.name) private var allExercises: [Exercise]

    let onSelect: (Exercise) -> Void

    @State private var selectedCategory: String?
    @State private var searchText = ""
    @State private var showCustomAdd = false
    @State private var customName = ""
    @State private var customCategory = "胸"

    let categories = ["胸", "背中", "脚", "肩", "腕", "腹"]

    var filteredExercises: [Exercise] {
        allExercises.filter { exercise in
            let matchesCategory = selectedCategory == nil || exercise.category == selectedCategory
            let matchesSearch = searchText.isEmpty || exercise.name.localizedCaseInsensitiveContains(searchText)
            return matchesCategory && matchesSearch
        }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                categoryFilter
                List {
                    ForEach(filteredExercises) { exercise in
                        Button {
                            onSelect(exercise)
                        } label: {
                            HStack {
                                VStack(alignment: .leading) {
                                    Text(exercise.name)
                                        .foregroundStyle(.primary)
                                    Text(exercise.category)
                                        .font(.caption)
                                        .foregroundStyle(.secondary)
                                }
                                Spacer()
                                if !exercise.isPreset {
                                    Text("カスタム")
                                        .font(.caption2)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 2)
                                        .background(.blue.opacity(0.1))
                                        .foregroundStyle(.blue)
                                        .clipShape(Capsule())
                                }
                            }
                        }
                    }
                }
                .searchable(text: $searchText, prompt: "種目を検索")
            }
            .navigationTitle("種目を選択")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showCustomAdd = true
                    } label: {
                        Label("追加", systemImage: "plus")
                    }
                }
            }
            .sheet(isPresented: $showCustomAdd) {
                customAddSheet
            }
        }
    }

    private var categoryFilter: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                FilterChip(title: "すべて", isSelected: selectedCategory == nil) {
                    selectedCategory = nil
                }
                ForEach(categories, id: \.self) { category in
                    FilterChip(title: category, isSelected: selectedCategory == category) {
                        selectedCategory = category == selectedCategory ? nil : category
                    }
                }
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
        }
        .background(.regularMaterial)
    }

    private var customAddSheet: some View {
        NavigationStack {
            Form {
                Section("種目名") {
                    TextField("例：ケーブルフライ", text: $customName)
                }
                Section("筋肉グループ") {
                    Picker("グループ", selection: $customCategory) {
                        ForEach(categories, id: \.self) { category in
                            Text(category).tag(category)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }
            .navigationTitle("カスタム種目を追加")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") {
                        customName = ""
                        showCustomAdd = false
                    }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("追加") {
                        saveCustomExercise()
                    }
                    .disabled(customName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                }
            }
        }
    }

    private func saveCustomExercise() {
        let trimmedName = customName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        let exercise = Exercise(name: trimmedName, category: customCategory, isPreset: false)
        modelContext.insert(exercise)
        try? modelContext.save()
        customName = ""
        showCustomAdd = false
    }
}

struct FilterChip: View {
    let title: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.subheadline)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(isSelected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(isSelected ? .white : .primary)
                .clipShape(Capsule())
        }
    }
}
