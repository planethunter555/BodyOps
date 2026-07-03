import SwiftUI

/// 筋トレ記録の新規作成時に表示するスタート画面。
/// 「種目から」「日付から」の2つの入力導線と、前回コピーのショートカットを提供する。
struct WorkoutEntryStartView: View {
    let lastSessionDate: Date?
    let onCopyLastSession: () -> Void
    let onPickExercise: () -> Void
    let onCopyFromDate: () -> Void

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                if let lastDate = lastSessionDate {
                    Button(action: onCopyLastSession) {
                        HStack {
                            Image(systemName: "arrow.counterclockwise.circle.fill")
                                .font(.title2)
                            VStack(alignment: .leading, spacing: 2) {
                                Text("前回のトレーニングをコピー")
                                    .font(.headline)
                                Text("\(Self.fmtDate(lastDate)) のメニューをそのまま読み込みます")
                                    .font(.caption)
                                    .opacity(0.85)
                            }
                            Spacer()
                            Image(systemName: "chevron.right")
                                .font(.caption)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                    }
                    .buttonStyle(.borderedProminent)

                    HStack {
                        VStack { Divider() }
                        Text("または")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        VStack { Divider() }
                    }
                    .padding(.vertical, 4)
                }

                methodCard(
                    icon: "dumbbell.fill",
                    title: "種目から始める",
                    description: "種目を選ぶと前回のセット内容が自動で入力されます",
                    action: onPickExercise
                )

                methodCard(
                    icon: "calendar.badge.clock",
                    title: "過去の日からコピー",
                    description: "カレンダーで日を選び、その日のメニュー全体を読み込みます",
                    action: onCopyFromDate
                )

                Spacer(minLength: 0)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    private func methodCard(icon: String, title: String, description: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.accentColor)
                    .frame(width: 44, height: 44)
                    .background(Color.accentColor.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
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

    private static func fmtDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d(E)"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}
