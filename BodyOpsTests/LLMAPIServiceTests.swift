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

    // MARK: - streamMessage (真のストリーミング)

    private func makeStreamingService(lines: [String], statusCode: Int = 200) -> LLMAPIService {
        LLMAPIService(session: mockSession, sseStreamer: MockSSEStreamer(lines: lines, statusCode: statusCode))
    }

    // TC-07: Claude SSEをイベント順に逐次パースする（テキスト+思考+usage）
    func test_streamMessage_claude_deliversOrderedEvents() async throws {
        let lines = [
            #"data: {"type":"message_start","message":{"usage":{"input_tokens":25}}}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"thinking_delta","thinking":"考えて"}}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":"Hello"}}"#,
            #"data: {"type":"content_block_delta","delta":{"type":"text_delta","text":" World"}}"#,
            #"data: {"type":"message_delta","usage":{"output_tokens":12}}"#,
            #"data: {"type":"message_stop"}"#
        ]
        let service = makeStreamingService(lines: lines)

        var events: [LLMStreamEvent] = []
        let stream = service.streamMessage(
            messages: [LLMMessage(role: "user", content: "hi")],
            system: "", provider: .claude, apiKey: "key"
        )
        for try await event in stream { events.append(event) }

        XCTAssertEqual(events, [
            .thinking("考えて"),
            .text("Hello"),
            .text(" World"),
            .usage(input: 25, output: 12)
        ])
    }

    // TC-08: OpenAI SSE（[DONE]終端+最終usageチャンク）
    func test_streamMessage_openai_deliversTextAndUsage() async throws {
        let lines = [
            #"data: {"choices":[{"delta":{"content":"Hi"}}]}"#,
            #"data: {"choices":[{"delta":{"content":" there"}}]}"#,
            #"data: {"choices":[],"usage":{"prompt_tokens":10,"completion_tokens":5}}"#,
            "data: [DONE]"
        ]
        let service = makeStreamingService(lines: lines)

        var events: [LLMStreamEvent] = []
        let stream = service.streamMessage(
            messages: [LLMMessage(role: "user", content: "hi")],
            system: "", provider: .openai, apiKey: "key"
        )
        for try await event in stream { events.append(event) }

        XCTAssertEqual(events, [
            .text("Hi"),
            .text(" there"),
            .usage(input: 10, output: 5)
        ])
    }

    // TC-09: Gemini SSE（累積usageMetadataは最後の値を採用）
    func test_streamMessage_gemini_usesLastCumulativeUsage() async throws {
        let lines = [
            #"data: {"candidates":[{"content":{"parts":[{"text":"やあ"}]}}],"usageMetadata":{"promptTokenCount":8,"candidatesTokenCount":2}}"#,
            #"data: {"candidates":[{"content":{"parts":[{"text":"！"}]}}],"usageMetadata":{"promptTokenCount":8,"candidatesTokenCount":6}}"#
        ]
        let service = makeStreamingService(lines: lines)

        var events: [LLMStreamEvent] = []
        let stream = service.streamMessage(
            messages: [LLMMessage(role: "user", content: "hi")],
            system: "", provider: .gemini, apiKey: "key"
        )
        for try await event in stream { events.append(event) }

        XCTAssertEqual(events, [
            .text("やあ"),
            .text("！"),
            .usage(input: 8, output: 6)
        ])
    }

    // TC-10: ストリーミングでも401はunauthorizedにマップされる
    func test_streamMessage_401_throwsUnauthorized() async {
        let service = makeStreamingService(lines: [], statusCode: 401)

        do {
            let stream = service.streamMessage(
                messages: [LLMMessage(role: "user", content: "hi")],
                system: "", provider: .claude, apiKey: "bad-key"
            )
            for try await _ in stream { }
            XCTFail("エラーが投げられるはず")
        } catch let error as LLMError {
            XCTAssertEqual(error, .unauthorized)
        } catch {
            XCTFail("予期しないエラー: \(error)")
        }
    }

    // TC-11: adaptive thinking対応モデルのストリーミングボディにはthinkingが付く
    func test_claudeStreamingBody_includesAdaptiveThinking() throws {
        let body = try service.buildRequestBody(
            messages: [LLMMessage(role: "user", content: "hi")],
            system: "", provider: .claude, modelName: "claude-sonnet-5", stream: true
        )
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertTrue(bodyString.contains(#""thinking""#))
        XCTAssertTrue(bodyString.contains(#""adaptive""#))
    }

    // TC-12: 非ストリーミング（PFC推定）ボディにはthinkingを付けない
    func test_claudeNonStreamingBody_omitsThinking() throws {
        let body = try service.buildRequestBody(
            messages: [LLMMessage(role: "user", content: "hi")],
            system: "", provider: .claude, modelName: "claude-sonnet-5", stream: false
        )
        let bodyString = String(data: body, encoding: .utf8) ?? ""
        XCTAssertFalse(bodyString.contains(#""thinking""#))
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

/// SSE行フィクスチャを流すモックストリーマー
struct MockSSEStreamer: SSELineStreaming {
    let lines: [String]
    let statusCode: Int

    func lines(for request: URLRequest) async throws -> (lines: AsyncThrowingStream<String, Error>, response: HTTPURLResponse) {
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: statusCode,
            httpVersion: nil,
            headerFields: nil
        )!
        let fixtureLines = lines
        let stream = AsyncThrowingStream<String, Error> { continuation in
            for line in fixtureLines {
                continuation.yield(line)
            }
            continuation.finish()
        }
        return (stream, response)
    }
}
