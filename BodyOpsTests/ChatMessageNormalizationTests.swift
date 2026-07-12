import XCTest
@testable import BodyOps

/// LLM APIへ送る会話履歴の正規化（role交互・空除外）のテスト
@MainActor
final class ChatMessageNormalizationTests: XCTestCase {

    // 送信失敗でAIの返信が無いままuserが続いたケース: マージされて交互になる
    func test_consecutiveUserMessages_areMerged() {
        let input = [
            LLMMessage(role: "user", content: "こんにちは"),
            LLMMessage(role: "assistant", content: "はい"),
            LLMMessage(role: "user", content: "今日のメニュー教えて"),
            LLMMessage(role: "user", content: "もう一度送ります")
        ]

        let result = ChatViewModel.normalizedForAPI(input)

        XCTAssertEqual(result.map(\.role), ["user", "assistant", "user"])
        XCTAssertTrue(result[2].content.contains("今日のメニュー教えて"))
        XCTAssertTrue(result[2].content.contains("もう一度送ります"))
    }

    // 先頭がassistantの場合は除外される（先頭はuserでなければならない）
    func test_leadingAssistant_isDropped() {
        let input = [
            LLMMessage(role: "assistant", content: "前の回答"),
            LLMMessage(role: "user", content: "質問")
        ]

        let result = ChatViewModel.normalizedForAPI(input)

        XCTAssertEqual(result.map(\.role), ["user"])
    }

    // 空メッセージは除外される
    func test_emptyMessages_areRemoved() {
        let input = [
            LLMMessage(role: "user", content: "質問"),
            LLMMessage(role: "assistant", content: "   "),
            LLMMessage(role: "user", content: "追加の質問")
        ]

        let result = ChatViewModel.normalizedForAPI(input)

        XCTAssertEqual(result.map(\.role), ["user"])
        XCTAssertTrue(result[0].content.contains("質問"))
        XCTAssertTrue(result[0].content.contains("追加の質問"))
    }

    // 交互の正常な履歴はそのまま
    func test_alternatingHistory_isUnchanged() {
        let input = [
            LLMMessage(role: "user", content: "A"),
            LLMMessage(role: "assistant", content: "B"),
            LLMMessage(role: "user", content: "C")
        ]

        let result = ChatViewModel.normalizedForAPI(input)

        XCTAssertEqual(result.map(\.content), ["A", "B", "C"])
    }
}
