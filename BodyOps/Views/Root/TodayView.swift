import SwiftUI
import SwiftData

struct TodayView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = TodayViewModel()

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 16) {
                    dateNavigationHeader
                    workoutSummaryCard
                    mealSummaryCard
                    encourageCard
                }
                .padding()
            }
            .navigationTitle("今日")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                viewModel.setup(context: modelContext)
            }
            .sheet(isPresented: $viewModel.showWorkoutSheet, onDismiss: workoutSheetDismissed) {
                WorkoutRecordSheet(date: viewModel.selectedDate)
            }
            .sheet(isPresented: $viewModel.showMealSheet, onDismiss: mealSheetDismissed) {
                MealRecordSheet(date: viewModel.selectedDate)
            }
        }
    }

    private var dateNavigationHeader: some View {
        HStack {
            Button {
                viewModel.goToPreviousDay()
            } label: {
                Image(systemName: "chevron.left")
                    .font(.title2)
                    .foregroundStyle(.primary)
            }

            Spacer()

            Text(viewModel.formattedDate)
                .font(.headline)

            Spacer()

            Button {
                viewModel.goToNextDay()
            } label: {
                Image(systemName: "chevron.right")
                    .font(.title2)
                    .foregroundStyle(viewModel.isToday ? .tertiary : .primary)
            }
            .disabled(viewModel.isToday)
        }
        .padding(.horizontal, 4)
    }

    private var workoutSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("筋トレ", systemImage: "dumbbell.fill")
                    .font(.headline)
                Spacer()
            }

            if viewModel.workoutSessions.isEmpty {
                emptyStateView(message: "筋トレの記録がありません")
            } else {
                HStack(spacing: 24) {
                    VStack {
                        Text("\(viewModel.exerciseCount)")
                            .font(.title2.bold())
                        Text("種目")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack {
                        Text(String(format: "%.0f", viewModel.totalVolume))
                            .font(.title2.bold())
                        Text("総ボリューム(kg)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }
            }

            Button {
                viewModel.showWorkoutSheet = true
            } label: {
                Label("筋トレを記録する", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var mealSummaryCard: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("食事", systemImage: "fork.knife")
                    .font(.headline)
                Spacer()
            }

            if viewModel.mealRecords.isEmpty {
                emptyStateView(message: "食事の記録がありません")
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text("\(Int(viewModel.totalCalories)) kcal")
                            .font(.title2.bold())
                        Spacer()
                    }
                    pfcRow(label: "P", value: viewModel.totalProtein, color: .blue)
                    pfcRow(label: "F", value: viewModel.totalFat, color: .yellow)
                    pfcRow(label: "C", value: viewModel.totalCarbs, color: .orange)
                }
            }

            Button {
                viewModel.showMealSheet = true
            } label: {
                Label("食事を記録する", systemImage: "plus.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var encourageCard: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label("あなたの記録", systemImage: "flame.fill")
                .font(.headline)
                .foregroundStyle(.orange)

            if let firstDate = viewModel.firstWorkoutDate {
                let days = Calendar.current.dateComponents([.day], from: Calendar.current.startOfDay(for: firstDate), to: Calendar.current.startOfDay(for: Date())).day ?? 0
                HStack(spacing: 24) {
                    VStack {
                        Text("Day \(days + 1)")
                            .font(.title2.bold())
                        Text("筋トレ開始から")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    VStack {
                        Text("\(viewModel.totalSessionCount)")
                            .font(.title2.bold())
                        Text("通算セッション")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Spacer()
                }

                Text(encourageMessage(days: days, sessions: viewModel.totalSessionCount))
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                Text("最初の筋トレ記録を追加しましょう！")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }

            if !viewModel.userGoal.isEmpty {
                Divider()
                HStack(alignment: .top, spacing: 6) {
                    Image(systemName: "target")
                        .foregroundStyle(.orange)
                        .font(.caption)
                    Text(viewModel.userGoal)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(3)
                }
            }
        }
        .padding()
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private func encourageMessage(days: Int, sessions: Int) -> String {
        switch days {
        case 0...7:   return "スタートダッシュ！最初の一歩を踏み出しました💪"
        case 8...30:  return "いいペースで続いています。継続は力なり！"
        case 31...90: return "1ヶ月以上継続中！習慣化できてきましたね🔥"
        case 91...180: return "3ヶ月以上！本当の変化が現れてくる時期です⚡️"
        case 181...365: return "半年継続！あなたの努力は本物です🏆"
        default:       return "1年以上継続！真のアスリートです🎖️"
        }
    }

    private func pfcRow(label: String, value: Double, color: Color) -> some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.caption.bold())
                .frame(width: 16)
                .foregroundStyle(color)
            Text(String(format: "%.1fg", value))
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private func emptyStateView(message: String) -> some View {
        Text(message)
            .font(.subheadline)
            .foregroundStyle(.secondary)
            .frame(maxWidth: .infinity, alignment: .center)
            .padding(.vertical, 8)
    }

    private func workoutSheetDismissed() {
        viewModel.fetchData()
    }

    private func mealSheetDismissed() {
        viewModel.fetchData()
    }
}
