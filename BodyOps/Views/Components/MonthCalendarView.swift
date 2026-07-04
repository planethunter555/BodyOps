import SwiftUI

/// 月表示のミニカレンダー共通コンポーネント。
/// 記録のある日にドットを表示し、過去日付の選択を提供する（未来日は選択不可）。
struct MonthCalendarView: View {
    @Binding var selectedDate: Date
    let markedDates: Set<Date>
    var dotColor: Color = .accentColor

    @State private var calendarMonth: Date

    init(selectedDate: Binding<Date>, markedDates: Set<Date>, dotColor: Color = .accentColor) {
        self._selectedDate = selectedDate
        self.markedDates = markedDates
        self.dotColor = dotColor
        self._calendarMonth = State(initialValue: Calendar.current.startOfMonth(for: selectedDate.wrappedValue))
    }

    var body: some View {
        VStack(spacing: 8) {
            monthHeader

            // LazyVGrid は List 内で recursive layout loop を起こすため
            // VStack + HStack の明示的な行レイアウトを使用
            VStack(spacing: 4) {
                HStack(spacing: 0) {
                    ForEach(["月", "火", "水", "木", "金", "土", "日"], id: \.self) { weekday in
                        Text(weekday)
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
        .onChange(of: selectedDate) { _, newDate in
            // 外部から選択日が変わった場合、表示月を追従させる
            let month = Calendar.current.startOfMonth(for: newDate)
            if month != calendarMonth {
                calendarMonth = month
            }
        }
    }

    // MARK: - Subviews

    private var monthHeader: some View {
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
    }

    private func dayCell(for date: Date) -> some View {
        let hasMark = markedDates.contains(Calendar.current.startOfDay(for: date))
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
                            hasMark
                            ? (isSelected ? Color.white : dotColor)
                            : Color.clear
                        )
                        .frame(width: 4, height: 4)
                }
            }
        }
        .disabled(isFuture)
        .buttonStyle(.plain)
    }

    // MARK: - Computation

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

    private var monthTitle: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy年M月"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: calendarMonth)
    }
}
