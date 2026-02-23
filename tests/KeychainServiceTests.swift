import XCTest
@testable import BodyOps

final class KeychainServiceTests: XCTestCase {

    let service = KeychainService.shared

    override func setUp() {
        super.setUp()
        // テスト前に全プロバイダーのキーをクリア
        LLMProvider.allCases.forEach { try? service.delete(forProvider: $0) }
    }

    override func tearDown() {
        super.tearDown()
        LLMProvider.allCases.forEach { try? service.delete(forProvider: $0) }
    }

    // TC-01: プロバイダー別に保存・取得できる
    func test_saveAndLoad_perProvider() throws {
        try service.save(apiKey: "claude-key-123", forProvider: .claude)
        try service.save(apiKey: "openai-key-456", forProvider: .openai)
        try service.save(apiKey: "gemini-key-789", forProvider: .gemini)

        XCTAssertEqual(service.load(forProvider: .claude), "claude-key-123")
        XCTAssertEqual(service.load(forProvider: .openai), "openai-key-456")
        XCTAssertEqual(service.load(forProvider: .gemini), "gemini-key-789")
    }

    // TC-01: プロバイダー間で干渉しない
    func test_providers_areIndependent() throws {
        try service.save(apiKey: "only-claude", forProvider: .claude)

        XCTAssertEqual(service.load(forProvider: .claude), "only-claude")
        XCTAssertNil(service.load(forProvider: .openai))
        XCTAssertNil(service.load(forProvider: .gemini))
    }

    // TC-02: 上書き保存できる
    func test_overwrite_returnsNewKey() throws {
        try service.save(apiKey: "old-key", forProvider: .claude)
        try service.save(apiKey: "new-key", forProvider: .claude)

        XCTAssertEqual(service.load(forProvider: .claude), "new-key")
    }

    // TC-03: 削除後はnilを返す
    func test_delete_returnsNil() throws {
        try service.save(apiKey: "to-delete", forProvider: .openai)
        try service.delete(forProvider: .openai)

        XCTAssertNil(service.load(forProvider: .openai))
    }

    // TC-04: 未保存はnilを返す
    func test_load_withoutSave_returnsNil() {
        XCTAssertNil(service.load(forProvider: .claude))
        XCTAssertNil(service.load(forProvider: .openai))
        XCTAssertNil(service.load(forProvider: .gemini))
    }

    // TC-05: 空文字列はnilとして扱う
    func test_save_emptyString_returnsNil() throws {
        try service.save(apiKey: "", forProvider: .claude)

        XCTAssertNil(service.load(forProvider: .claude))
    }
}
