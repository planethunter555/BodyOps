import SwiftUI

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.scenePhase) private var scenePhase

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
        .onChange(of: scenePhase) { _, newPhase in
            let exportService = ICloudExportService.shared
            if newPhase == .background && exportService.isEnabled {
                // バックグラウンド移行時はすぐにサスペンドされる可能性があるためdebounceを待たず即実行する
                Task { await exportService.exportNow(context: modelContext) }
            }
        }
    }
}
