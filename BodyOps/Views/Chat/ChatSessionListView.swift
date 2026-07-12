import SwiftUI

/// 過去のチャットセッション一覧。タップで読み込み、スワイプで削除できる。
struct ChatSessionListView: View {
    @Environment(\.dismiss) private var dismiss

    let currentTag: String
    let summaries: [ChatSessionSummary]
    let onSelect: (String) -> Void
    let onDelete: (String) -> Void

    @State private var items: [ChatSessionSummary]

    init(currentTag: String,
         summaries: [ChatSessionSummary],
         onSelect: @escaping (String) -> Void,
         onDelete: @escaping (String) -> Void) {
        self.currentTag = currentTag
        self.summaries = summaries
        self.onSelect = onSelect
        self.onDelete = onDelete
        self._items = State(initialValue: summaries)
    }

    var body: some View {
        NavigationStack {
            Group {
                if items.isEmpty {
                    ContentUnavailableView(
                        "会話履歴はありません",
                        systemImage: "clock.arrow.circlepath",
                        description: Text("AIコーチとの会話がここに保存されます")
                    )
                } else {
                    List {
                        Section {
                            ForEach(items) { summary in
                                sessionRow(summary)
                            }
                            .onDelete(perform: deleteItems)
                        } footer: {
                            Text("会話は最新\(ChatHistoryStore.maxSessions)件・\(ChatHistoryStore.maxAgeDays)日間保存されます")
                        }
                    }
                }
            }
            .navigationTitle("会話履歴")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
    }

    private func sessionRow(_ summary: ChatSessionSummary) -> some View {
        Button {
            onSelect(summary.tag)
            dismiss()
        } label: {
            VStack(alignment: .leading, spacing: 4) {
                HStack {
                    Text(Self.fmtDate(summary.lastMessageAt))
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if summary.tag == currentTag {
                        Text("表示中")
                            .font(.caption2.bold())
                            .padding(.horizontal, 6)
                            .padding(.vertical, 2)
                            .background(Color.accentColor.opacity(0.15))
                            .foregroundStyle(Color.accentColor)
                            .clipShape(Capsule())
                    }
                    Spacer()
                    Text("\(summary.messageCount)件")
                        .font(.caption2)
                        .foregroundStyle(.tertiary)
                }
                Text(summary.preview)
                    .font(.subheadline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
            }
            .padding(.vertical, 2)
        }
    }

    private func deleteItems(at offsets: IndexSet) {
        for index in offsets {
            onDelete(items[index].tag)
        }
        items.remove(atOffsets: offsets)
    }

    private static func fmtDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M/d(E) HH:mm"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}
