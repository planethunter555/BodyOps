import SwiftUI
import SwiftData
import Charts

struct GraphView: View {
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

    @State private var selectedPeriod: GraphPeriod = .threeMonths
    @State private var selectedExerciseName: String = ""

    enum GraphPeriod: String, CaseIterable {
        case oneMonth = "1ヶ月"
        case threeMonths = "3ヶ月"
        case sixMonths = "6ヶ月"
        case all = "全期間"

        var days: Int? {
            switch self {
            case .oneMonth: return 30
            case .threeMonths: return 90
            case .sixMonths: return 180
            case .all: return nil
            }
        }
    }

    var filteredSessions: [WorkoutSession] {
        guard let days = selectedPeriod.days else { return sessions }
        let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
        return sessions.filter { $0.date >= cutoff }
    }

    var exerciseNames: [String] {
        let names = filteredSessions.flatMap { $0.sets }.compactMap { $0.exercise?.name }
        return Array(Set(names)).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                periodPicker
                weeklyVolumeChart
                exerciseProgressChart
                muscleGroupFrequencyChart
            }
            .padding()
        }
        .navigationTitle("グラフ")
        .navigationBarTitleDisplayMode(.inline)
    }

    private var periodPicker: some View {
        Picker("期間", selection: $selectedPeriod) {
            ForEach(GraphPeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    private var weeklyVolumeChart: some View {
        let weeklyData = computeWeeklyVolume()
        return VStack(alignment: .leading, spacing: 8) {
            Text("週別総ボリューム")
                .font(.headline)
            if weeklyData.isEmpty {
                Text("データがありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(weeklyData, id: \.week) { item in
                    BarMark(
                        x: .value("週", item.week),
                        y: .value("ボリューム", item.volume)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(height: 150)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var exerciseProgressChart: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("種目別最高重量推移")
                    .font(.headline)
                Spacer()
                Picker("種目", selection: $selectedExerciseName) {
                    Text("選択...").tag("")
                    ForEach(exerciseNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }
                .pickerStyle(.menu)
            }

            let data = maxWeightProgress(for: selectedExerciseName)
            if data.isEmpty || selectedExerciseName.isEmpty {
                Text(selectedExerciseName.isEmpty ? "種目を選択してください" : "データがありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 150)
            } else {
                Chart(data, id: \.date) { item in
                    LineMark(
                        x: .value("日付", item.date),
                        y: .value("重量", item.weight)
                    )
                    .foregroundStyle(Color.green)
                    PointMark(
                        x: .value("日付", item.date),
                        y: .value("重量", item.weight)
                    )
                    .foregroundStyle(Color.green)
                }
                .frame(height: 150)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var muscleGroupFrequencyChart: some View {
        let frequencyData = computeMuscleGroupFrequency()
        return VStack(alignment: .leading, spacing: 8) {
            Text("筋肉グループ別頻度（過去4週間）")
                .font(.headline)
            if frequencyData.isEmpty {
                Text("データがありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 100)
            } else {
                Chart(frequencyData, id: \.category) { item in
                    BarMark(
                        x: .value("頻度", item.count),
                        y: .value("グループ", item.category)
                    )
                    .foregroundStyle(Color.orange)
                }
                .frame(height: 200)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func computeWeeklyVolume() -> [(week: String, volume: Double)] {
        let calendar = Calendar.current
        var weekMap: [String: Double] = [:]
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d週"
        formatter.locale = Locale(identifier: "ja_JP")
        for session in filteredSessions {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: session.date)
            let weekStart = calendar.date(from: components) ?? session.date
            let key = formatter.string(from: weekStart)
            weekMap[key, default: 0] += session.totalVolume
        }
        return weekMap.sorted { $0.key < $1.key }.map { (week: $0.key, volume: $0.value) }
    }

    private func maxWeightProgress(for exerciseName: String) -> [(date: Date, weight: Double)] {
        guard !exerciseName.isEmpty else { return [] }
        var result: [(date: Date, weight: Double)] = []
        for session in filteredSessions {
            let sets = session.sets.filter { $0.exercise?.name == exerciseName }
            if let maxWeight = sets.map({ $0.weight }).max() {
                result.append((date: session.date, weight: maxWeight))
            }
        }
        return result.sorted { $0.date < $1.date }
    }

    private func computeMuscleGroupFrequency() -> [(category: String, count: Int)] {
        let cutoff = Calendar.current.date(byAdding: .day, value: -28, to: Date()) ?? Date()
        let recentSessions = sessions.filter { $0.date >= cutoff }
        let categories = ["胸", "背中", "脚", "肩", "腕", "腹"]
        return categories.map { category in
            let count = recentSessions.filter { session in
                session.sets.contains { $0.exercise?.category == category }
            }.count
            return (category: category, count: count)
        }
    }
}
