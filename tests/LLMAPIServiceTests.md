# LLMAPIService テストシナリオ

## 対象
`Services/LLMAPIService.swift`

## テストコード配置先
`BodyOps/BodyOpsTests/LLMAPIServiceTests.swift`

## 方針
実際のAPIは呼ばない。URLSessionをモックしてHTTPレスポンスを差し替えてテストする。

---

## シナリオ一覧

### TC-01: プロバイダー別に正しいエンドポイントURLを使用する
- provider = .claude のとき api.anthropic.com を呼ぶ
- provider = .openai のとき api.openai.com を呼ぶ
- provider = .gemini のとき generativelanguage.googleapis.com を呼ぶ

### TC-02: 401レスポンスで LLMError.unauthorized を返す
- モックが401を返す状態でsendMessage()を呼ぶ
- LLMError.unauthorizedが投げられる

### TC-03: 429レスポンスで LLMError.rateLimited を返す
- モックが429を返す状態でsendMessage()を呼ぶ
- LLMError.rateLimitedが投げられる

### TC-04: 500レスポンスで LLMError.serverError を返す
- モックが500を返す状態でsendMessage()を呼ぶ
- LLMError.serverErrorが投げられる

### TC-05: 正常なSSEストリームをパースしてテキストチャンクを返す
- Claudeフォーマットの正常なSSEデータをモックで返す
- AsyncThrowingStreamが正しいテキストチャンクを配信する

### TC-06: 画像付きメッセージをBase64エンコードして送信する
- UIImageをメッセージに添付してsendMessage()を呼ぶ
- リクエストボディにBase64エンコードされた画像データが含まれる
