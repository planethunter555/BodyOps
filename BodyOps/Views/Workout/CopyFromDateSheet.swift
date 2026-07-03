import SwiftUI
import SwiftData

/// 過去の日付を選んでその日のメニュー全体をコピーするシート。
/// カレンダーで日を選ぶと下にプレビューが表示され、「この内容で読み込む」で確定する。
struct CopyFromDateSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.date) private var allSessions: [WorkoutSession]

    let onCopy: ([WorkoutExerciseEntry]) -> Void

    @State private var selectedDate: Date = Calendar.current.startOfDay(for: Date())
    @State private var calendarMonth: Date = Calendar.current.startOfMonth(for: Date())

    private var prefillService: WorkoutPrefillService {
        WorkoutPrefillService(context: modelContext)
    }

    private var previewEntries: [WorkoutExerciseEntry] {
        prefillService.entries(for: selectedDate)
    }

    var body: some View {
        NavigationStack {
            List {
                Section("日付を選択") {
                    calendarView
                }
                previewSection
            }
            .navigationTitle("過去の日からコピー")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { dismiss() }
                }
            }
            .safeAreaInset(edge: .bottom) {
                copyButton
            }
            .onAppear {
                // 直近のトレーニング日を初期選択にする（プレビューが空で始まらないように）
                if let recent = prefillService.mostRecentSessionDate(before: Date().addingTimeInterval(86400)) {
                    selectedDate = Calendar.current.startOfDay(for: recent)
                    calendarMonth = Calendar.current.startOfMonth(for: recent)
                }
            }
        }
    }

    // MARK: - Preview

    @ViewBuilder
    private var previewSection: some View {
        let entries = previewEntries
        Section("この日のメニュー") {
            if entries.isEmpty {
                Text("この日の記録はありません")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 3) {
                        Label(entry.exercise.name, systemImage: "dumbbell.fill")
                            .font(.subheadline.bold())
                        Text(setSummary(entry.sets))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 28)
                    }
                    .padding(.vertical, 2)
                }
            }
        }
    }

    private var copyButton: some View {
        Button {
            onCopy(previewEntries)
            dismiss()
        } label: {
            Label("この内容で読み込む", systemImage: "doc.on.doc")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .disabled(previewEntries.isEmpty)
        .padding()
        .background(.bar)
    }

    private func setSummary(_ sets: [WorkoutSetEntry]) -> String {
        sets.map { "\(Self.fmtWeight($0.weight))kg×\($0.reps)" }
            .joined(separator: " / ")
    }

    private static func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }

    // MARK: - Calendar

    private var calendarView: some View {
        VStack(spacing: 8) {
            HStack {
                Button {
                    calendarMonth = Calendar.current.date(byAdding: .month, value: -1, to: calendarMonth) ?? calendarMonth
                } label: {
                    Image(systemName: "chevron.left")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                Spacer()
                Text(monthTitle)
                    .font(.subheadline.bold())
                Spacer()
                Button {
                    let next = Calendar.current.date(byAdding: .month, value: 1, to: calendarMonth) ?? calendarMonth
                    if next <= Calendar.current.startOfMonth(for: Date()) {
                        calendarMonth = next
                    }
                } label: {
                    Image(systemName: "chevron.right")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }

            // LazyVGrid は List 内で recursive layout loop を起こすため
            // VStack + HStack の明示的な行レイアウトを使用
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { wd in
                        Text(wd)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .frame(maxWidth: .infinity)
                    }
                }
                let days = paddedCalendarDays
                let rowCount = days.count / 7
                ForEach(0..<rowCount, id: \.self) { row in
                    HStack(spacing: 0) {
                        ForEach(0..<7) { col in
                            let item = days[row * 7 + col]
                            Group {
                                if let day = item {
                                    dayCell(for: day)
                                } else {
                                    Color.clear.frame(height: 32)
                                }
                            }
                            .frame(maxWidth: .infinity)
                        }
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func dayCell(for date: Date) -> some View {
        let hasSession = sessionDates.contains(Calendar.current.startOfDay(for: date))
        let isSelected = Calendar.current.isDate(date, inSameDayAs: selectedDate)
        let isFuture = date > Date()
        return Button {
            if !isFuture {
                selectedDate = Calendar.current.startOfDay(for: date)
            }
        } label: {
            ZStack {
                Circle()
                    .fill(isSelected ? Color.accentColor : Color.clear)
                    .frame(width: 30, height: 30)
                VStack(spacing: 2) {
                    Text("\(Calendar.current.component(.day, from: date))")
                        .font(.caption)
                        .foregroundStyle(
                            isFuture ? Color.secondary.opacity(0.4)
                            : isSelected ? .white
                            : .primary
                        )
                    Circle()
                        .fill(
                            hasSession
                            ? (isSelected ? Color.white : Color.accentColor)
                            : Color.clear
                        )
                        .frame(width: 4, height: 4)
                }
            }
        }
        .disabled(isFuture)
        .buttonStyle(.plain)
    }

    private var calendarDays: [Date?] {
        let calendar = Calendar.current
        guard let range = calendar.range(of: .day, in: .month, for: calendarMonth) else { return [] }
        let weekday = calendar.component(.weekday, from: calendarMonth)
        let offset = (weekday - 2 + 7) % 7
        var days: [Date?] = Array(repeating: nil, count: offset)
        for day in range {
            if let date = calendar.date(byAdding: .day, value: day - 1, to: calendarMonth) {
                days.append(date)
            }
        }
        return days
    }

    /// VStack+HStack レイアウト用に7の倍数へパディングした配列
    private var paddedCalendarDays: [Date?] {
        var days = calendarDays
        let remainder = days.count % 7
        if remainder != 0 {
            days += Array(repeating: nil, count: 7 - remainder)
        }
        return days
    }

    private var sessionDates: Set<Date> {
        Set(allSessions.map { Calendar.current.startOfDay(for: $0.date) })
    }

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: calendarMonth)
    }
}
