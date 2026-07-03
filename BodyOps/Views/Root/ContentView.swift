import SwiftUI

struct ContentView: View {
    var body: some View {
        TabView {
            RecordTabView()
                .tabItem { Label("記録", systemImage: "square.and.pencil") }
            GraphView()
                .tabItem { Label("グラフ", systemImage: "chart.xyaxis.line") }
            AIChatView()
                .tabItem { Label("AIコーチ", systemImage: "brain") }
            SettingsView()
                .tabItem { Label("設定", systemImage: "gearshape") }
        }
    }
}
