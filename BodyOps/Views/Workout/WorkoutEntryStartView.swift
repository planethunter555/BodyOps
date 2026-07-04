import SwiftUI
import SwiftData

/// 筋トレ記録の新規作成時に表示するスタート画面。
/// カレンダーを常時表示し、「過去の日のメニュー読み込み（既定は前回のトレーニング）」と
/// 「種目から始める」の導線を提供する。
struct WorkoutEntryStartView: View {
    @Environment(\.modelContext) private var modelContext
    @Query(sort: \WorkoutSession.date) private var allSessions: [WorkoutSession]

    let onLoadEntries: ([WorkoutExerciseEntry]) -> Void
    let onPickExercise: () -> Void

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())
    @State private var didSetInitialDate = false

    private var prefillService: WorkoutPrefillService {
        WorkoutPrefillService(context: modelContext)
    }

    private var sessionDates: Set<Date> {
        Set(allSessions.map { Calendar.current.startOfDay(for: $0.date) })
    }

    private var mostRecentSessionDay: Date? {
        allSessions.last.map { Calendar.current.startOfDay(for: $0.date) }
    }

    private var previewEntries: [WorkoutExerciseEntry] {
        prefillService.entries(for: selectedDate)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                calendarCard
                dayPreviewCard

                HStack {
                    VStack { Divider() }
                    Text("または")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    VStack { Divider() }
                }

                exercisePickerCard

                Spacer(minLength: 0)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .onAppear {
            // 初期選択は直近のトレーニング日（プレビューが「前回のトレーニング」になる）
            guard !didSetInitialDate else { return }
            didSetInitialDate = true
            if let recent = mostRecentSessionDay {
                selectedDate = recent
            }
        }
    }

    // MARK: - Cards

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("過去の記録からコピー", systemImage: "calendar.badge.clock")
                .font(.subheadline.bold())
            Text("日付を選ぶと、その日のメニューを読み込めます")
                .font(.caption)
                .foregroundStyle(.secondary)
            MonthCalendarView(selectedDate: $selectedDate, markedDates: sessionDates)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    @ViewBuilder
    private var dayPreviewCard: some View {
        let entries = previewEntries
        let isLastSession = mostRecentSessionDay.map { Calendar.current.isDate($0, inSameDayAs: selectedDate) } ?? false
        VStack(alignment: .leading, spacing: 8) {
            Text(isLastSession
                 ? "前回のトレーニング（\(Self.fmtDate(selectedDate))）"
                 : "\(Self.fmtDate(selectedDate)) のメニュー")
                .font(.subheadline.bold())

            if entries.isEmpty {
                Text("この日の記録はありません")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(entries) { entry in
                    VStack(alignment: .leading, spacing: 2) {
                        Label(entry.exercise.name, systemImage: "dumbbell.fill")
                            .font(.caption.bold())
                        Text(setSummary(entry.sets))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.leading, 24)
                    }
                }
                Button {
                    onLoadEntries(entries)
                } label: {
                    Label(isLastSession ? "前回のメニューを読み込む" : "この日のメニューを読み込む",
                          systemImage: "arrow.counterclockwise.circle.fill")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 4)
                }
                .buttonStyle(.borderedProminent)
                .padding(.top, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var exercisePickerCard: some View {
        Button(action: onPickExercise) {
            HStack(spacing: 14) {
                Image(systemName: "dumbbell.fill")
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("種目から始める")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text("種目を選ぶと前回のセット内容が自動で入力されます")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }

    // MARK: - Helpers

    private func setSummary(_ sets: [WorkoutSetEntry]) -> String {
        sets.map { "\(Self.fmtWeight($0.weight))kg×\($0.reps)" }
            .joined(separator: " / ")
    }

    private static func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }

    private static func fmtDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}
