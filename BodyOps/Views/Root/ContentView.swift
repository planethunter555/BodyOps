import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            Text("今日")
                .tabItem { Label("今日", systemImage: "calendar") }
            Text("履歴")
                .tabItem { Label("履歴", systemImage: "clock.arrow.circlepath") }
            Text("AIアドバイス")
                .tabItem { Label("アドバイス", systemImage: "brain") }
            Text("設定")
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
