import Foundation
import SwiftData

/// チャットセッションの一覧表示用サマリー
struct ChatSessionSummary: Identifiable {
    var id: String { tag }
    let tag: String
    let startedAt: Date
    let lastMessageAt: Date
    let preview: String
    let messageCount: Int
}

/// 過去のチャットセッションの一覧・読み込み・保持期間管理を担うストア。
/// ChatMessage は sessionTag ごとに1つの会話としてグルーピングされる。
enum ChatHistoryStore {
    /// 保持する最大セッション数（超過分は古い順に削除）
    static let maxSessions = 30
    /// 最終メッセージからの保持日数（超過セッションは削除）
    static let maxAgeDays = 90
    /// 1メッセージのみのセッションをレガシー残骸とみなして削除する経過日数
    static let staleSingleMessageDays = 7

    /// 全セッションのサマリーを新しい順に返す
    static func sessions(in context: ModelContext) -> [ChatSessionSummary] {
        let descriptor = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt)])
        let all = (try? context.fetch(descriptor)) ?? []
        return summaries(from: all).sorted { $0.lastMessageAt > $1.lastMessageAt }
    }

    /// 指定セッションのメッセージを時系列順に返す
    static func messages(tag: String, in context: ModelContext) -> [ChatMessage] {
        let descriptor = FetchDescriptor<ChatMessage>(
            predicate: #Predicate { $0.sessionTag == tag },
            sortBy: [SortDescriptor(\.createdAt)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    /// セッションを丸ごと削除する
    static func deleteSession(tag: String, in context: ModelContext) {
        for message in messages(tag: tag, in: context) {
            context.delete(message)
        }
        try? context.save()
    }

    /// 保持ポリシーを適用して古いセッションを削除する。
    /// - 最終メッセージが maxAgeDays を超えたセッション
    /// - 新しい順で maxSessions を超えたセッション
    /// - 1メッセージのみで staleSingleMessageDays を超えたセッション（旧仕様の起動毎UUIDの残骸）
    /// currentTag のセッションは常に保護する。
    static func prune(in context: ModelContext, keepingCurrent currentTag: String, now: Date = Date()) {
        let descriptor = FetchDescriptor<ChatMessage>(sortBy: [SortDescriptor(\.createdAt)])
        let all = (try? context.fetch(descriptor)) ?? []
        let allSummaries = summaries(from: all).sorted { $0.lastMessageAt > $1.lastMessageAt }

        let ageCutoff = Calendar.current.date(byAdding: .day, value: -maxAgeDays, to: now) ?? now
        let staleCutoff = Calendar.current.date(byAdding: .day, value: -staleSingleMessageDays, to: now) ?? now

        var tagsToDelete: Set<String> = []
        for (index, summary) in allSummaries.enumerated() {
            guard summary.tag != currentTag else { continue }
            if summary.lastMessageAt < ageCutoff {
                tagsToDelete.insert(summary.tag)
            } else if index >= maxSessions {
                tagsToDelete.insert(summary.tag)
            } else if summary.messageCount <= 1 && summary.lastMessageAt < staleCutoff {
                tagsToDelete.insert(summary.tag)
            }
        }

        guard !tagsToDelete.isEmpty else { return }
        for message in all where tagsToDelete.contains(message.sessionTag) {
            context.delete(message)
        }
        try? context.save()
    }

    // MARK: - Private

    private static func summaries(from messages: [ChatMessage]) -> [ChatSessionSummary] {
        var grouped: [String: [ChatMessage]] = [:]
        for message in messages {
            grouped[message.sessionTag, default: []].append(message)
        }
        return grouped.compactMap { tag, msgs in
            guard let first = msgs.first, let last = msgs.last else { return nil }
            let previewSource = msgs.first { $0.role == "user" && !$0.content.isEmpty } ?? first
            let preview = String(previewSource.content.prefix(60))
            return ChatSessionSummary(
                tag: tag,
                startedAt: first.createdAt,
                lastMessageAt: last.createdAt,
                preview: preview.isEmpty ? "（画像のみ）" : preview,
                messageCount: msgs.count
            )
        }
    }
}
