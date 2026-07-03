import XCTest
import SwiftData
@testable import BodyOps

final class ChatHistoryStoreTests: XCTestCase {

    var container: ModelContainer!
    var context: ModelContext!

    override func setUp() {
        super.setUp()
        let config = ModelConfiguration(isStoredInMemoryOnly: true)
        container = try! ModelContainer(for: ChatMessage.self, configurations: config)
        context = ModelContext(container)
    }

    override func tearDown() {
        container = nil
        context = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeSession(tag: String, messageCount: Int, daysAgo: Int) {
        let base = Calendar.current.date(byAdding: .day, value: -daysAgo, to: Date())!
        for index in 0..<messageCount {
            let msg = ChatMessage(
                role: index % 2 == 0 ? "user" : "assistant",
                content: "メッセージ\(index) (\(tag))",
                sessionTag: tag
            )
            msg.createdAt = base.addingTimeInterval(TimeInterval(index * 60))
            context.insert(msg)
        }
        try! context.save()
    }

    // MARK: - sessions()

    func test_sessions_groupsByTagWithSummary() {
        makeSession(tag: "session-a", messageCount: 4, daysAgo: 2)
        makeSession(tag: "session-b", messageCount: 2, daysAgo: 1)

        let summaries = ChatHistoryStore.sessions(in: context)

        XCTAssertEqual(summaries.count, 2)
        // 新しい順（session-bが先頭）
        XCTAssertEqual(summaries[0].tag, "session-b")
        XCTAssertEqual(summaries[0].messageCount, 2)
        XCTAssertEqual(summaries[1].tag, "session-a")
        XCTAssertEqual(summaries[1].messageCount, 4)
        // プレビューは最初のユーザーメッセージ
        XCTAssertTrue(summaries[1].preview.contains("メッセージ0"))
    }

    // MARK: - messages(tag:)

    func test_messages_returnsOnlyTaggedSessionInOrder() {
        makeSession(tag: "session-a", messageCount: 3, daysAgo: 2)
        makeSession(tag: "session-b", messageCount: 2, daysAgo: 1)

        let messages = ChatHistoryStore.messages(tag: "session-a", in: context)

        XCTAssertEqual(messages.count, 3)
        XCTAssertTrue(messages.allSatisfy { $0.sessionTag == "session-a" })
        XCTAssertEqual(messages.map(\.content).first, "メッセージ0 (session-a)")
    }

    // MARK: - deleteSession

    func test_deleteSession_removesAllMessagesOfTag() {
        makeSession(tag: "session-a", messageCount: 3, daysAgo: 2)
        makeSession(tag: "session-b", messageCount: 2, daysAgo: 1)

        ChatHistoryStore.deleteSession(tag: "session-a", in: context)

        XCTAssertTrue(ChatHistoryStore.messages(tag: "session-a", in: context).isEmpty)
        XCTAssertEqual(ChatHistoryStore.messages(tag: "session-b", in: context).count, 2)
    }

    // MARK: - prune

    func test_prune_deletesSessionsOverMaxCount() {
        // maxSessions + 5 セッション作成（すべて新しい）
        for index in 0..<(ChatHistoryStore.maxSessions + 5) {
            makeSession(tag: "session-\(index)", messageCount: 2, daysAgo: 0)
        }

        ChatHistoryStore.prune(in: context, keepingCurrent: "session-0")

        let remaining = ChatHistoryStore.sessions(in: context)
        XCTAssertLessThanOrEqual(remaining.count, ChatHistoryStore.maxSessions + 1) // +1は保護対象
    }

    func test_prune_deletesSessionsOlderThanMaxAge() {
        makeSession(tag: "old-session", messageCount: 3, daysAgo: ChatHistoryStore.maxAgeDays + 10)
        makeSession(tag: "recent-session", messageCount: 3, daysAgo: 5)

        ChatHistoryStore.prune(in: context, keepingCurrent: "recent-session")

        let tags = ChatHistoryStore.sessions(in: context).map(\.tag)
        XCTAssertFalse(tags.contains("old-session"))
        XCTAssertTrue(tags.contains("recent-session"))
    }

    func test_prune_protectsCurrentSession() {
        makeSession(tag: "current-but-old", messageCount: 3, daysAgo: ChatHistoryStore.maxAgeDays + 10)

        ChatHistoryStore.prune(in: context, keepingCurrent: "current-but-old")

        XCTAssertEqual(ChatHistoryStore.messages(tag: "current-but-old", in: context).count, 3)
    }

    func test_prune_deletesStaleSingleMessageSessions() {
        // 旧仕様（起動毎UUID）の残骸: 1メッセージのみで8日前
        makeSession(tag: "legacy-stale", messageCount: 1, daysAgo: ChatHistoryStore.staleSingleMessageDays + 1)
        // 1メッセージでも最近のものは残す
        makeSession(tag: "fresh-single", messageCount: 1, daysAgo: 0)

        ChatHistoryStore.prune(in: context, keepingCurrent: "other")

        let tags = ChatHistoryStore.sessions(in: context).map(\.tag)
        XCTAssertFalse(tags.contains("legacy-stale"))
        XCTAssertTrue(tags.contains("fresh-single"))
    }
}
