# WorkoutCopyService テストシナリオ

## 対象
`Services/WorkoutCopyService.swift`

## テストコード配置先
`BodyOps/BodyOpsTests/WorkoutCopyServiceTests.swift`

---

## シナリオ一覧

### TC-01: 前回セッションの全種目・セット・重量・回数をコピーできる
- 3種目・各3セットを持つWorkoutSessionを作成する
- copyPreviousSession()を呼ぶ
- 新しいセッションに同じ種目・セット数・重量・回数が追加される

### TC-02: 前回セッションが存在しない場合はnilを返す
- WorkoutSessionが0件の状態でcopyPreviousSession()を呼ぶ
- nilが返る（コピー不可）

### TC-03: 直前のセットをコピーして次のセットを追加できる
- 1セット（重量60kg・回数10回）が存在するセッションで copyLastSet()を呼ぶ
- weight=60, reps=10の新しいセットが追加される

### TC-04: コピー後に重量・回数を変更しても元データに影響しない
- 前回セッションをコピーする
- コピー先のセットの重量を変更する
- 元のWorkoutSessionの重量が変わっていない

### TC-05: volumeがコピー時に正しく計算される
- 重量70kg・回数8回のセットをコピーする
- コピーされたセットのvolumeが560（=70×8）になっている
