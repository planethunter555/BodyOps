import SwiftUI

/// 「記録」タブ。今日のサマリーと履歴カレンダーをセグメントで切り替える。
struct RecordTabView: View {
    enum Mode: String, CaseIterable {
        case today = "今日"
        case calendar = "カレンダー"
    }

    @State private var mode: Mode = .today

    var body: some View {
        NavigationStack {
            Group {
                switch mode {
                case .today:
                    TodayContentView()
                case .calendar:
                    HistoryContentView()
                }
            }
            .navigationTitle("記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .principal) {
                    Picker("表示", selection: $mode) {
                        ForEach(Mode.allCases, id: \.self) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 220)
                }
            }
        }
    }
}
