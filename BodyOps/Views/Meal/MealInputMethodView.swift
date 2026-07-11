import SwiftUI
import SwiftData
import UIKit

/// 食事記録の入力方法選択画面（Step 1）。
/// 「写真からAI推定」「テキストからAI推定」「手動で入力」の3方式を明確に提示し、
/// カレンダーからの過去の食事コピーも提供する。
struct MealInputMethodView: View {
    @Query(sort: \MealRecord.recordedAt) private var allMeals: [MealRecord]

    @Binding var mealType: String
    let onTakePhoto: () -> Void
    let onPickFromLibrary: () -> Void
    let onChooseTextAI: () -> Void
    let onChooseManual: () -> Void
    let onCopyMeal: (MealRecord) -> Void

    @State private var selectedDate = Calendar.current.startOfDay(for: Date())

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    private var mealDates: Set<Date> {
        Set(allMeals.map { Calendar.current.startOfDay(for: $0.recordedAt) })
    }

    private var mealsOfSelectedDay: [MealRecord] {
        let start = Calendar.current.startOfDay(for: selectedDate)
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start) ?? start
        return allMeals.filter { $0.recordedAt >= start && $0.recordedAt < end }
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("食事タイプ", selection: $mealType) {
                    ForEach(MealType.allCases, id: \.rawValue) { type in
                        Text(type.label).tag(type.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                photoAICard

                methodCard(
                    icon: "keyboard",
                    iconColor: .blue,
                    title: "テキストからAI推定",
                    description: "「ご飯1杯、鶏胸肉200g」のように入力するとAIがカロリー・PFCを推定します"
                ) {
                    onChooseTextAI()
                }

                methodCard(
                    icon: "pencil.line",
                    iconColor: .gray,
                    title: "手動で入力",
                    description: "AIを使わず、カロリー・PFCを自分で入力します"
                ) {
                    onChooseManual()
                }

                HStack {
                    VStack { Divider() }
                    Text("過去の食事からコピー")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize()
                    VStack { Divider() }
                }
                .padding(.top, 4)

                calendarCard

                if !mealsOfSelectedDay.isEmpty {
                    dayMealsCard
                }

                Spacer(minLength: 0)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
    }

    // MARK: - Cards

    /// 写真からAI推定。ポップアップを挟まず、カメラ/ライブラリのボタンをカード内に直接置く。
    private var photoAICard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 14) {
                Image(systemName: "camera.fill")
                    .font(.title2)
                    .foregroundStyle(Color.green)
                    .frame(width: 44, height: 44)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text("写真からAI推定")
                        .font(.headline)
                    Text("食事の写真からAIがカロリー・PFCを自動推定します")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
            }
            HStack(spacing: 10) {
                if cameraAvailable {
                    Button {
                        onTakePhoto()
                    } label: {
                        Label("カメラで撮影", systemImage: "camera")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)

                    Button {
                        onPickFromLibrary()
                    } label: {
                        Label("ライブラリ", systemImage: "photo.on.rectangle")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .tint(.green)
                } else {
                    Button {
                        onPickFromLibrary()
                    } label: {
                        Label("ライブラリから選択", systemImage: "photo.on.rectangle")
                            .font(.subheadline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(.green)
                }
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var calendarCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("日付を選ぶと、その日の食事を再利用できます")
                .font(.caption)
                .foregroundStyle(.secondary)
            MonthCalendarView(selectedDate: $selectedDate, markedDates: mealDates, dotColor: .orange)
        }
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private var dayMealsCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("\(Self.fmtDate(selectedDate)) の食事")
                .font(.subheadline.bold())

            ForEach(mealsOfSelectedDay) { meal in
                Button {
                    onCopyMeal(meal)
                } label: {
                    HStack(spacing: 8) {
                        Text(MealType(rawValue: meal.mealType)?.label ?? meal.mealType)
                            .font(.caption.bold())
                            .padding(.horizontal, 8)
                            .padding(.vertical, 3)
                            .background(Color.green.opacity(0.15))
                            .foregroundStyle(.green)
                            .clipShape(Capsule())
                        VStack(alignment: .leading, spacing: 1) {
                            Text(meal.mealDescription.isEmpty ? "（写真のみ）" : meal.mealDescription)
                                .font(.caption)
                                .foregroundStyle(.primary)
                                .lineLimit(1)
                            Text("\(Int(meal.calories))kcal  P\(Int(meal.protein)) F\(Int(meal.fat)) C\(Int(meal.carbs))")
                                .font(.caption2)
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        Label("コピー", systemImage: "doc.on.doc")
                            .font(.caption)
                            .foregroundStyle(Color.accentColor)
                    }
                    .padding(.vertical, 4)
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 14))
    }

    private func methodCard(icon: String, iconColor: Color, title: String, description: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(iconColor)
                    .frame(width: 44, height: 44)
                    .background(iconColor.opacity(0.12))
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
