import SwiftUI
import SwiftData

extension WorkoutSession: Identifiable {}

struct HistoryView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.date, order: .reverse) private var allSessions: [WorkoutSession]
    @Query(sort: \MealRecord.recordedAt, order: .reverse) private var allMeals: [MealRecord]

    @State private var currentMonth: Date = Calendar.current.startOfMonth(for: Date())
    @State private var selectedDate: Date?
    @State private var showGraphView = false
    @State private var showCSVImport = false
    @State private var editingSession: WorkoutSession?
    @State private var showWorkoutSheet = false
    @State private var deletingSession: WorkoutSession?
    @State private var deletingMeal: MealRecord?

    let categories = ["胸", "背中", "脚", "肩", "腕", "腹"]

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    calendarSection
                    if let date = selectedDate {
                        dayDetailSection(for: date)
                    }
                    lastTrainedSection
                }
                .padding()
            }
            .navigationTitle("履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        showGraphView = true
                    } label: {
                        Label("グラフで見る", systemImage: "chart.xyaxis.line")
                    }
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        showCSVImport = true
                    } label: {
                        Label("CSVインポート", systemImage: "square.and.arrow.down")
                    }
                }
            }
            .navigationDestination(isPresented: $showGraphView) {
                GraphView()
            }
            .sheet(isPresented: $showCSVImport) {
                CSVImportSheet()
            }
            .sheet(item: $editingSession) { session in
                WorkoutRecordSheet(date: session.date, editingSession: session)
            }
            .sheet(isPresented: $showWorkoutSheet) {
                if let date = selectedDate {
                    WorkoutRecordSheet(date: date)
                }
            }
            .alert("筋トレ記録を削除", isPresented: Binding(
                get: { deletingSession != nil },
                set: { if !$0 { deletingSession = nil } }
            )) {
                Button("削除", role: .destructive) {
                    if let s = deletingSession { deleteSession(s) }
                }
                Button("キャンセル", role: .cancel) { deletingSession = nil }
            } message: {
                Text("この筋トレ記録を削除しますか？この操作は取り消せません。")
            }
            .alert("食事記録を削除", isPresented: Binding(
                get: { deletingMeal != nil },
                set: { if !$0 { deletingMeal = nil } }
            )) {
                Button("削除", role: .destructive) {
                    if let m = deletingMeal { deleteMeal(m) }
                }
                Button("キャンセル", role: .cancel) { deletingMeal = nil }
            } message: {
                Text("この食事記録を削除しますか？この操作は取り消せません。")
            }
        }
    }

    private var calendarSection: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    currentMonth = Calendar.current.date(byAdding: .month, value: -1, to: currentMonth) ?? currentMonth
                } label: {
                    Image(systemName: "chevron.left")
                }

                Spacer()

                Text(monthTitle)
                    .font(.headline)

                Spacer()

                Button {
                    let next = Calendar.current.date(byAdding: .month, value: 1, to: currentMonth) ?? currentMonth
                    if next <= Calendar.current.startOfMonth(for: Date()) {
                        currentMonth = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                }
            }
            .padding(.horizontal)

            calendarGrid
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var calendarGrid: some View {
        let days = daysInMonth()
        let columns = Array(repeating: GridItem(.flexible()), count: 7)
        return LazyVGrid(columns: columns, spacing: 8) {
            ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { weekday in
                Text(weekday)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            ForEach(0..<days.count, id: \.self) { index in
                if let day = days[index] {
                    dayCell(for: day)
                } else {
                    Color.clear.frame(height: 32)
                }
            }
        }
    }

    private func dayCell(for date: Date) -> some View {
        let hasWorkout = sessionsForDate(date).isEmpty == false
        let isSelected = selectedDate.map { Calendar.current.isDate($0, inSameDayAs: date) } ?? false
        let isToday = Calendar.current.isDateInToday(date)
        return Button {
            selectedDate = Calendar.current.isDate(date, inSameDayAs: selectedDate ?? Date.distantPast)
                ? nil : date
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : (isToday ? Color.accentColor.opacity(0.2) : Color.clear))
                    .frame(width: 32, height: 32)
                VStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.caption)
                        .foregroundStyle(isSelected ? .white : .primary)
                    if hasWorkout {
                        Circle()
                            .fill(isSelected ? Color.white : Color.accentColor)
                            .frame(width: 4, height: 4)
                    }
                }
            }
        }
    }

    private func dayDetailSection(for date: Date) -> some View {
        let sessions = sessionsForDate(date)
        let meals = mealsForDate(date)
        let isFuture = date > Date()
        return VStack(alignment: .leading, spacing: 12) {
            Text(dayDetailTitle(date))
                .font(.headline)

            if sessions.isEmpty && meals.isEmpty {
                Text("この日の記録はありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            ForEach(sessions) { session in
                workoutDetailCard(session: session)
            }

            ForEach(meals) { meal in
                mealDetailCard(meal: meal)
            }

            if !isFuture {
                Button {
                    showWorkoutSheet = true
                } label: {
                    Label("筋トレを記録する", systemImage: "plus.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 6)
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func workoutDetailCard(session: WorkoutSession) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("筋トレ", systemImage: "dumbbell.fill")
                    .font(.subheadline.bold())
                Spacer()
                Text(String(format: "%.0f kg 総ボリューム", session.totalVolume))
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    editingSession = session
                } label: {
                    Image(systemName: "pencil.circle")
                        .foregroundStyle(Color.accentColor)
                }
                .buttonStyle(.plain)
                Button {
                    deletingSession = session
                } label: {
                    Image(systemName: "trash.circle")
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
            }
            let grouped = Dictionary(grouping: session.sets) { $0.exercise?.name ?? "不明" }
            ForEach(grouped.keys.sorted(), id: \.self) { exerciseName in
                let sets = (grouped[exerciseName] ?? []).sorted { $0.setNumber < $1.setNumber }
                VStack(alignment: .leading, spacing: 2) {
                    Text(exerciseName)
                        .font(.caption.bold())
                    ForEach(sets, id: \.id) { set in
                        HStack(spacing: 4) {
                            Text("\(set.setNumber).")
                                .font(.caption2)
                                .foregroundStyle(.tertiary)
                                .frame(width: 16, alignment: .trailing)
                            Text(String(format: "%.1fkg × %d回", set.weight, set.reps))
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            if !session.memo.isEmpty {
                Text("メモ: \(session.memo)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
    }

    private func mealTypeLabel(_ raw: String) -> String {
        switch raw {
        case "breakfast": return "朝食"
        case "lunch": return "昼食"
        case "dinner": return "夕食"
        case "snack": return "間食"
        default: return raw
        }
    }

    private func mealDetailCard(meal: MealRecord) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Label(mealTypeLabel(meal.mealType), systemImage: "fork.knife")
                    .font(.subheadline.bold())
                Spacer()
                Text("\(Int(meal.calories)) kcal")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Button {
                    deletingMeal = meal
                } label: {
                    Image(systemName: "trash.circle")
                        .foregroundStyle(Color.red)
                }
                .buttonStyle(.plain)
            }
            if !meal.mealDescription.isEmpty {
                Text(meal.mealDescription)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }
            HStack(spacing: 12) {
                Text("P: \(String(format: "%.0fg", meal.protein))")
                Text("F: \(String(format: "%.0fg", meal.fat))")
                Text("C: \(String(format: "%.0fg", meal.carbs))")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
        }
        .padding(.vertical, 4)
    }

    private var lastTrainedSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("筋肉グループ別 最終トレーニング日")
                .font(.headline)

            ForEach(categories, id: \.self) { category in
                HStack {
                    Text(category)
                        .font(.subheadline)
                        .frame(width: 40, alignment: .leading)
                    Spacer()
                    Text(lastTrainedDate(for: category))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func sessionsForDate(_ date: Date) -> [WorkoutSession] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return allSessions.filter { $0.date >= start && $0.date < end }
    }

    private func mealsForDate(_ date: Date) -> [MealRecord] {
        let start = Calendar.current.startOfDay(for: date)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return allMeals.filter { $0.recordedAt >= start && $0.recordedAt < end }
    }

    private func lastTrainedDate(for category: String) -> String {
        let categorySessions = allSessions.filter { session in
            session.sets.contains { $0.exercise?.category == category }
        }
        guard let latest = categorySessions.first else { return "記録なし" }
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: latest.date)
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: currentMonth)
    }

    private func dayDetailTitle(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }

    private func deleteSession(_ session: WorkoutSession) {
        modelContext.delete(session)
        try? modelContext.save()
    }

    private func deleteMeal(_ meal: MealRecord) {
        modelContext.delete(meal)
        try? modelContext.save()
    }

    private func daysInMonth() -> [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: currentMonth) else { return [] }
        // iOS weekday: 1=Sun, 2=Mon, ..., 7=Sat
        // Convert to Monday-first 0-based offset: Mon=0, Tue=1, ..., Sun=6
        let weekday = calendar.component(.weekday, from: currentMonth)
        let monFirstOffset = (weekday - 2 + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: monFirstOffset)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: currentMonth) {
                days.append(date)
            }
        }
        return days
    }
}
