import SwiftUI
import UIKit

extension View {
    /// キーボード上部に「完了」ボタンを追加する。
    /// 数値キーボードなどリターンキーが無いキーボードでも閉じられるようにする共通手段。
    func keyboardDoneButton() -> some View {
        toolbar {
            ToolbarItemGroup(placement: .keyboard) {
                Spacer()
                Button("完了") {
                    UIApplication.shared.sendAction(
                        #selector(UIResponder.resignFirstResponder),
                        to: nil, from: nil, for: nil
                    )
                }
            }
        }
    }
}
