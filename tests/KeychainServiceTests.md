# KeychainService テストシナリオ

## 対象
`Services/KeychainService.swift`

## テストコード配置先
`BodyOps/BodyOpsTests/KeychainServiceTests.swift`

---

## シナリオ一覧

### TC-01: プロバイダー別にAPIキーを保存・取得できる
- Claude / OpenAI / Gemini それぞれのキーを保存する
- 各プロバイダーのload()が保存したキーを返す
- プロバイダーAのキーがプロバイダーBのload()に影響しない

### TC-02: 上書き保存ができる
- 同じプロバイダーに別のキーを再保存する
- load()が新しいキーを返す

### TC-03: 削除後はnilを返す
- キーを保存する
- delete()を呼ぶ
- load()がnilを返す

### TC-04: 未保存のプロバイダーはnilを返す
- 何も保存していない状態でload()を呼ぶ
- nilが返る

### TC-05: 空文字列を保存した場合はnilを返す
- 空文字列を保存する
- load()がnilを返す（空キーは無効として扱う）
