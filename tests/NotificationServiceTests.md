# NotificationService テストシナリオ

## 対象
`Services/NotificationService.swift`

## テストコード配置先
`BodyOps/BodyOpsTests/NotificationServiceTests.swift`

## 方針
UNUserNotificationCenterをモックして実際の通知を発火させずにテストする。

---

## シナリオ一覧

### TC-01: 曜日・時刻を指定すると通知リクエストが登録される
- weekdays=[月,水,金], hour=20, minute=0 で schedule()を呼ぶ
- UNNotificationRequestが3件登録される（各曜日1件）

### TC-02: isEnabled=falseでOFFにすると全通知がキャンセルされる
- 通知を登録した後 cancelAll()を呼ぶ
- 登録済みリクエストが0件になる

### TC-03: 再設定すると古い通知がキャンセルされ新しい設定で登録される
- 月・水・金で登録する
- 月・木で再登録する
- 登録リクエストが2件（月・木）になる

### TC-04: 通知リクエストのIDが一意である
- 複数の曜日で通知を登録する
- 全リクエストのIDが重複しない
