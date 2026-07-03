import SwiftUI
import SwiftData
import Charts

struct GraphView: View {
    @Query(sort: \WorkoutSession.date) private var sessions: [WorkoutSession]

    @State private var selectedPeriod: GraphPeriod = .threeMonths
    @State private var selectedExerciseName: String = ""
    @State private var customStart: Date = Calendar.current.date(byAdding: .month, value: -1, to: Date()) ?? Date()
    @State private var customEnd: Date = Date()

    enum GraphPeriod: String, CaseIterable {
        case oneWeek = "1週間"
        case oneMonth = "1ヶ月"
        case threeMonths = "3ヶ月"
        case sixMonths = "6ヶ月"
        case oneYear = "1年"
        case all = "全期間"
        case custom = "期間指定"

        var days: Int? {
            switch self {
            case .oneWeek: return 7
            case .oneMonth: return 30
            case .threeMonths: return 90
            case .sixMonths: return 180
            case .oneYear: return 365
            case .all, .custom: return nil
            }
        }
    }

    var filteredSessions: [WorkoutSession] {
        switch selectedPeriod {
        case .custom:
            let start = Calendar.current.startOfDay(for: min(customStart, customEnd))
            let endDay = Calendar.current.startOfDay(for: max(customStart, customEnd))
            let end = Calendar.current.date(byAdding: .day, value: 1, to: endDay) ?? endDay
            return sessions.filter { $0.date >= start && $0.date < end }
        default:
            guard let days = selectedPeriod.days else { return sessions }
            let cutoff = Calendar.current.date(byAdding: .day, value: -days, to: Date()) ?? Date()
            return sessions.filter { $0.date >= cutoff }
        }
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
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    summaryCard
                    periodPicker
                    weeklyVolumeChart
                    exerciseProgressChart
                }
                .padding()
            }
            .navigationTitle("グラフ")
            .navigationBarTitleDisplayMode(.inline)
        }
    }

    // MARK: - Summary Card

    /// モチベーション用サマリー（今週vs先週・今月のセッション数・連続記録週数）
    private var summaryCard: some View {
        let thisWeek = weekVolume(offset: 0)
        let lastWeek = weekVolume(offset: -1)
        return VStack(alignment: .leading, spacing: 12) {
            Label("今週のトレーニング", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            HStack(spacing: 20) {
                VStack(alignment: .leading, spacing: 2) {
                    Text(String(format: "%.0f kg", thisWeek))
                        .font(.title2.bold())
                    Text("今週の総ボリューム")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if lastWeek > 0 {
                        let ratio = (thisWeek - lastWeek) / lastWeek * 100
                        HStack(spacing: 2) {
                            Image(systemName: ratio >= 0 ? "arrow.up.right" : "arrow.down.right")
                            Text(String(format: "%+.0f%% 先週比", ratio))
                        }
                        .font(.caption.bold())
                        .foregroundStyle(ratio >= 0 ? .green : .red)
                    }
                }
                Spacer()
                VStack(spacing: 2) {
                    Text("\(monthSessionCount)")
                        .font(.title2.bold())
                    Text("今月の回数")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                VStack(spacing: 2) {
                    Text("\(consecutiveWeeks)")
                        .font(.title2.bold())
                    Text("連続週")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    // MARK: - Period Picker

    private var periodPicker: some View {
        VStack(spacing: 8) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(GraphPeriod.allCases, id: \.self) { period in
                        Button {
                            selectedPeriod = period
                        } label: {
                            Text(period.rawValue)
                                .font(.subheadline)
                                .padding(.horizontal, 14)
                                .padding(.vertical, 6)
                                .background(
                                    selectedPeriod == period
                                    ? Color.accentColor
                                    : Color(.secondarySystemGroupedBackground)
                                )
                                .foregroundStyle(selectedPeriod == period ? .white : .primary)
                                .clipShape(Capsule())
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.horizontal, 2)
            }

            if selectedPeriod == .custom {
                HStack {
                    DatePicker("開始", selection: $customStart, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                    Text("〜")
                        .foregroundStyle(.secondary)
                    DatePicker("終了", selection: $customEnd, in: ...Date(), displayedComponents: .date)
                        .labelsHidden()
                    Spacer()
                }
                .padding(.top, 4)
            }
        }
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

    /// 現在からoffset週分ずらした週の総ボリューム（offset: 0=今週, -1=先週）
    private func weekVolume(offset: Int) -> Double {
        let calendar = Calendar.current
        guard let base = calendar.date(byAdding: .weekOfYear, value: offset, to: Date()),
              let interval = calendar.dateInterval(of: .weekOfYear, for: base) else { return 0 }
        return sessions
            .filter { interval.contains($0.date) }
            .reduce(0) { $0 + $1.totalVolume }
    }

    /// 今月のセッション数
    private var monthSessionCount: Int {
        let calendar = Calendar.current
        guard let interval = calendar.dateInterval(of: .month, for: Date()) else { return 0 }
        return sessions.filter { interval.contains($0.date) }.count
    }

    /// 連続で記録がある週数。今週に記録がなければ先週から遡る（週の途中で途切れ扱いにしない）
    private var consecutiveWeeks: Int {
        let calendar = Calendar.current
        let weeksWithSession: Set<Date> = Set(sessions.compactMap { session in
            calendar.dateInterval(of: .weekOfYear, for: session.date)?.start
        })
        guard !weeksWithSession.isEmpty else { return 0 }

        guard var cursor = calendar.dateInterval(of: .weekOfYear, for: Date())?.start else { return 0 }
        if !weeksWithSession.contains(cursor) {
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { return 0 }
            cursor = prev
        }
        var count = 0
        while weeksWithSession.contains(cursor) {
            count += 1
            guard let prev = calendar.date(byAdding: .weekOfYear, value: -1, to: cursor) else { break }
            cursor = prev
        }
        return count
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
