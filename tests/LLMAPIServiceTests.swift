import XCTest
@testable import BodyOps

final class LLMAPIServiceTests: XCTestCase {

    var mockSession: MockURLSession!
    var service: LLMAPIService!

    override func setUp() {
        super.setUp()
        mockSession = MockURLSession()
        service = LLMAPIService(session: mockSession)
    }

    // TC-01: プロバイダー別に正しいエンドポイントを使用する
    func test_endpoint_claude() {
        let url = service.endpointURL(for: .claude)
        XCTAssertTrue(url.absoluteString.contains("api.anthropic.com"))
    }

    func test_endpoint_openai() {
        let url = service.endpointURL(for: .openai)
        XCTAssertTrue(url.absoluteString.contains("api.openai.com"))
    }

    func test_endpoint_gemini() {
        let url = service.endpointURL(for: .gemini)
        XCTAssertTrue(url.absoluteString.contains("generativelanguage.googleapis.com"))
    }

    // TC-02: 401 → LLMError.unauthorized
    func test_401_throwsUnauthorized() async {
        mockSession.responseStatusCode = 401
        mockSession.responseData = Data()

        do {
            var stream = service.sendMessage(
                messages: [LLMMessage(role: "user", content: "test")],
                system: "",
                provider: .claude,
                apiKey: "invalid-key"
            )
            for try await _ in stream { }
            XCTFail("エラーが投げられるはず")
        } catch let error as LLMError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }

    // TC-03: 429 → LLMError.rateLimited
    func test_429_throwsRateLimited() async {
        mockSession.responseStatusCode = 429
        mockSession.responseData = Data()

        do {
            var stream = service.sendMessage(
                messages: [LLMMessage(role: "user", content: "test")],
                system: "",
                provider: .openai,
                apiKey: "key"
            )
            for try await _ in stream { }
            XCTFail("エラーが投げられるはず")
        } catch let error as LLMError {
            XCTAssertEqual(error, .rateLimited)
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }

    // TC-04: 500 → LLMError.serverError
    func test_500_throwsServerError() async {
        mockSession.responseStatusCode = 500
        mockSession.responseData = Data()

        do {
            var stream = service.sendMessage(
                messages: [LLMMessage(role: "user", content: "test")],
                system: "",
                provider: .claude,
                apiKey: "key"
            )
            for try await _ in stream { }
            XCTFail("エラーが投げられるはず")
        } catch let error as LLMError {
            XCTAssertEqual(error, .serverError)
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }

    // TC-05: 正常なSSEストリームをパースしてテキストチャンクを返す（Claudeフォーマット）
    func test_validSSEStream_deliversTextChunks() async throws {
        let sseData = """
        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}

        data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" World"}}

        data: {"type":"message_stop"}

        """.data(using: .utf8)!

        mockSession.responseStatusCode = 200
        mockSession.responseData = sseData

        var chunks: [String] = []
        let stream = service.sendMessage(
            messages: [LLMMessage(role: "user", content: "hi")],
            system: "",
            provider: .claude,
            apiKey: "valid-key"
        )
        for try await chunk in stream {
            chunks.append(chunk)
        }

        XCTAssertEqual(chunks, ["Hello", " World"])
    }

    // TC-06: 画像付きメッセージにBase64データが含まれる
    func test_imageMessage_containsBase64() throws {
        let imageData = Data([0xFF, 0xD8, 0xFF]) // 最小限のJPEGヘッダー
        let message = LLMMessage(role: "user", content: "この食事は？", imageData: imageData)
        let body = try service.buildRequestBody(
            messages: [message],
            system: "",
            provider: .claude
        )
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains("base64"), "Base64エンコードされた画像データが含まれている")
        XCTAssertTrue(bodyString.contains(imageData.base64EncodedString()))
    }
}

// MARK: - Mock

final class MockURLSession: URLSessionProtocol {
    var responseStatusCode: Int = 200
    var responseData: Data = Data()

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: responseStatusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        return (responseData, response)
    }
}
