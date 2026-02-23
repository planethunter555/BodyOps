import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            TodayView()
                .tabItem { Label("今日", systemImage: "calendar") }
            HistoryView()
                .tabItem { Label("履歴", systemImage: "clock.arrow.circlepath") }
            Text("AIアドバイス")
                .tabItem { Label("アドバイス", systemImage: "brain") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
