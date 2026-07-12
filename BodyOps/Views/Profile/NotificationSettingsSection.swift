import SwiftUI

/// 設定画面の通知セクション。状態は親（SettingsView）が保持し、保存も親の保存ボタンで行う。
struct NotificationSettingsSection: View {
    @Binding var notificationsEnabled: Bool
    @Binding var selectedWeekdays: Set<Int>
    @Binding var notificationTime: Date

    var body: some View {
        Section("通知") {
            Toggle("トレーニングリマインダー", isOn: $notificationsEnabled)
            if notificationsEnabled {
                weekdayPickerRow
                DatePicker("通知時刻", selection: $notificationTime, displayedComponents: .hourAndMinute)
            }
        }
    }

    private var weekdayPickerRow: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("曜日")
                .font(.subheadline)
                .foregroundStyle(.secondary)
            HStack(spacing: 6) {
                ForEach([(1, "日"), (2, "月"), (3, "火"), (4, "水"), (5, "木"), (6, "金"), (7, "土")], id: \.0) { day, label in
                    weekdayButton(day: day, label: label)
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func weekdayButton(day: Int, label: String) -> some View {
        let selected = selectedWeekdays.contains(day)
        return Button {
            if selectedWeekdays.contains(day) {
                selectedWeekdays.remove(day)
            } else {
                selectedWeekdays.insert(day)
            }
        } label: {
            Text(label)
                .font(.caption.bold())
                .frame(width: 32, height: 32)
                .background(selected ? Color.accentColor : Color(.systemGray5))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }
}
