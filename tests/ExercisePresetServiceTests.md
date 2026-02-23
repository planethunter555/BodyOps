# ExercisePresetService テストシナリオ

## 対象
`Services/ExercisePresetService.swift`

## テストコード配置先
`BodyOps/BodyOpsTests/ExercisePresetServiceTests.swift`

---

## シナリオ一覧

### TC-01: 初回実行で60種目が投入される
- 空のModelContainerでseedIfNeeded()を呼ぶ
- Exercise が60件存在する

### TC-02: 2回呼んでも重複しない（冪等性）
- seedIfNeeded()を2回呼ぶ
- Exercise が60件のまま（120件にならない）

### TC-03: 全種目がisPreset = trueで登録される
- seedIfNeeded()後、全Exerciseのispresetがtrueである

### TC-04: 6カテゴリが全て存在する
- 胸・背中・脚・肩・腕・腹 それぞれに1件以上のExerciseが存在する

### TC-05: 主要種目が含まれている
- ベンチプレス・スクワット・デッドリフトが存在する
