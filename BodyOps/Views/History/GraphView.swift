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

    /// 全セッションでの実施回数上位10種目
    var top10Exercises: [String] {
        var countMap: [String: Int] = [:]
        for session in sessions {
            let names = Set(session.sets.compactMap { $0.exercise?.name })
            for name in names { countMap[name, default: 0] += 1 }
        }
        return countMap.sorted { $0.value > $1.value }.prefix(10).map { $0.key }
    }

    /// 全種目名（カスタムピッカー用）
    var allExerciseNames: [String] {
        let names = sessions.flatMap { $0.sets }.compactMap { $0.exercise?.name }
        return Array(Set(names)).sorted()
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                periodPicker
                weeklyVolumeChart
                exerciseProgressChart
            }
            .padding()
        }
        .navigationTitle("グラフ")
        .navigationBarTitleDisplayMode(.inline)
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        Picker("期間", selection: $selectedPeriod) {
            ForEach(GraphPeriod.allCases, id: \.self) { period in
                Text(period.rawValue).tag(period)
            }
        }
        .pickerStyle(.segmented)
    }

    // MARK: - Weekly Volume Chart

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
                Chart(weeklyData, id: \.weekStart) { item in
                    BarMark(
                        x: .value("週", item.weekStart, unit: .weekOfYear),
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

    // MARK: - Exercise Progress Chart

    private var exerciseProgressChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("種目別最高重量推移")
                .font(.headline)

            // 上位10種目を常時表示
            ForEach(top10Exercises, id: \.self) { name in
                exerciseCard(name)
            }

            // 11番目: 任意種目ピッカー + グラフ
            customExerciseCard
        }
    }

    private func exerciseCard(_ name: String) -> some View {
        let data = maxWeightProgress(for: name)
        return VStack(alignment: .leading, spacing: 6) {
            Text(name)
                .font(.subheadline.bold())
            if data.isEmpty {
                Text("この期間にデータがありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
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
                .frame(height: 100)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var customExerciseCard: some View {
        let data = maxWeightProgress(for: selectedExerciseName)
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(selectedExerciseName.isEmpty ? "種目を選択" : selectedExerciseName)
                    .font(.subheadline.bold())
                Spacer()
                Menu {
                    ForEach(allExerciseNames, id: \.self) { name in
                        Button(name) { selectedExerciseName = name }
                    }
                } label: {
                    Label("種目を選択", systemImage: "chevron.up.chevron.down")
                        .font(.caption)
                }
            }
            if selectedExerciseName.isEmpty {
                Text("上のメニューから種目を選択してください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else if data.isEmpty {
                Text("この期間にデータがありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, minHeight: 80)
            } else {
                Chart(data, id: \.date) { item in
                    LineMark(
                        x: .value("日付", item.date),
                        y: .value("重量", item.weight)
                    )
                    .foregroundStyle(Color.accentColor)
                    PointMark(
                        x: .value("日付", item.date),
                        y: .value("重量", item.weight)
                    )
                    .foregroundStyle(Color.accentColor)
                }
                .frame(height: 100)
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Compute Helpers

    private func computeWeeklyVolume() -> [(weekStart: Date, volume: Double)] {
        let calendar = Calendar.current
        var weekMap: [Date: Double] = [:]
        for session in filteredSessions {
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: session.date)
            let weekStart = calendar.date(from: components) ?? session.date
            weekMap[weekStart, default: 0] += session.totalVolume
        }
        return weekMap.sorted { $0.key < $1.key }.map { (weekStart: $0.key, volume: $0.value) }
    }

    private func maxWeightProgress(for exerciseName: String) -> [(date: Date, weight: Double)] {
        guard !exerciseName.isEmpty else { return [] }
        return filteredSessions.compactMap { session in
            let maxWeight = session.sets
                .filter { $0.exercise?.name == exerciseName }
                .map { $0.weight }
                .max()
            return maxWeight.map { (date: session.date, weight: $0) }
        }
        .sorted { $0.date < $1.date }
    }
}
