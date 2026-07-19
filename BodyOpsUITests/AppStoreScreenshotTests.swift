import XCTest

/// App Store 用スクリーンショットを自動撮影するUIテスト。
/// `-seedScreenshotData` でサンプルデータを投入した状態で各画面をキャプチャする。
/// 撮影結果は .xcresult 内の添付として保存され、後で xcresulttool で書き出す。
final class AppStoreScreenshotTests: XCTestCase {

    private var app: XCUIApplication!

    override func setUp() {
        super.setUp()
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchArguments = ["-seedScreenshotData"]
        app.launch()
    }

    func testCaptureScreenshots() {
        // 1. 記録タブ（今日）— 起動直後の状態
        _ = app.staticTexts["筋トレ"].waitForExistence(timeout: 10)
        sleep(1)
        capture("01_record_today")

        // 2. 筋トレ記録のスタート画面（カレンダー＋前回メニュー）
        if app.buttons["筋トレを記録する"].waitForExistence(timeout: 5) {
            app.buttons["筋トレを記録する"].tap()
            sleep(2)
            capture("02_workout_start")
            dismissSheet()
        }

        // 3. 食事入力の方法選択画面
        if app.buttons["食事を記録する"].waitForExistence(timeout: 5) {
            app.buttons["食事を記録する"].tap()
            sleep(2)
            capture("03_meal_input")
            dismissSheet()
        }

        // 4. グラフタブ
        if app.tabBars.buttons["グラフ"].waitForExistence(timeout: 5) {
            app.tabBars.buttons["グラフ"].tap()
            sleep(2)
            capture("04_graph")
        }

        // 5. AIコーチタブ（会話の復元）
        if app.tabBars.buttons["AIコーチ"].waitForExistence(timeout: 5) {
            app.tabBars.buttons["AIコーチ"].tap()
            sleep(2)
            capture("05_ai_coach")
        }
    }

    // MARK: - Helpers

    private func capture(_ name: String) {
        let shot = XCUIScreen.main.screenshot()
        let attachment = XCTAttachment(screenshot: shot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func dismissSheet() {
        for label in ["閉じる", "キャンセル"] {
            let button = app.buttons[label]
            if button.exists {
                button.tap()
                sleep(1)
                return
            }
        }
    }
}
