import SwiftUI
import SwiftData
import UIKit

@main
struct BodyOpsApp: App {
    private let container: ModelContainer?
    private let initError: String?

    init() {
        let schema = Schema([
            UserProfile.self,
            Exercise.self,
            WorkoutSession.self,
            WorkoutSet.self,
            ChatMessage.self,
            MealRecord.self,
            NotificationSetting.self,
            LLMSetting.self,
            APIUsageRecord.self
        ])

        var diagnosticLines: [String] = [
            "SwiftData ModelContainer diagnostics",
            ModelContainerDiagnostics.storeFilesReport()
        ]

        do {
            let inMemoryConfiguration = ModelConfiguration(
                schema: schema,
                isStoredInMemoryOnly: true,
                cloudKitDatabase: .none
            )
            _ = try ModelContainer(for: schema, configurations: inMemoryConfiguration)
            diagnosticLines.append("スキーマのみ: OK")
        } catch {
            diagnosticLines.append("スキーマのみ: NG")
            diagnosticLines.append(ModelContainerDiagnostics.format(error: error))
        }

        var productionContainer: ModelContainer?
        do {
            let configuration = ModelConfiguration(schema: schema, cloudKitDatabase: .none)
            productionContainer = try ModelContainer(for: schema, configurations: configuration)
            diagnosticLines.append("本番ストア: OK")
        } catch {
            diagnosticLines.append("本番ストア: NG")
            diagnosticLines.append(ModelContainerDiagnostics.format(error: error))
        }

        let diagnosticReport = diagnosticLines.joined(separator: "\n\n")
        print("[BodyOps][ModelContainer]\n\(diagnosticReport)")

        container = productionContainer
        initError = productionContainer == nil ? diagnosticReport : nil
    }

    var body: some Scene {
        WindowGroup {
            if let c = container {
                ContentView()
                    .onAppear {
                        let service = ExercisePresetService(context: c.mainContext)
                        try? service.seedIfNeeded()
                        if ScreenshotSeeder.isEnabled {
                            ScreenshotSeeder.seed(into: c.mainContext)
                        }
                    }
                    .modelContainer(c)
            } else {
                DataErrorView(message: initError ?? "不明なエラー")
            }
        }
    }
}

private struct DataErrorView: View {
    let message: String

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 60))
                    .foregroundStyle(.orange)
                Text("データベースエラー")
                    .font(.title2.bold())
                Text("アプリのデータを読み込めませんでした。下の診断情報をコピーして共有してください。")
                    .multilineTextAlignment(.center)
                    .foregroundStyle(.secondary)
                Button("診断情報をコピー") {
                    UIPasteboard.general.string = message
                }
                .buttonStyle(.borderedProminent)
                Text(message)
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.primary)
                    .textSelection(.enabled)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .multilineTextAlignment(.leading)
                    .padding(12)
                    .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 8))
            }
            .padding(32)
        }
    }
}

enum ModelContainerDiagnostics {
    static func format(error: Error) -> String {
        format(error: error, label: "Error", depth: 0)
    }

    static func storeFilesReport(
        applicationSupportURL: URL = .applicationSupportDirectory,
        fileManager: FileManager = .default
    ) -> String {
        let filenames = ["default.store", "default.store-shm", "default.store-wal"]
        var lines = ["Store files (metadata only):"]
        for filename in filenames {
            let url = applicationSupportURL.appendingPathComponent(filename)
            let exists = fileManager.fileExists(atPath: url.path)
            if exists {
                let attributes = try? fileManager.attributesOfItem(atPath: url.path)
                let size = (attributes?[.size] as? NSNumber)?.int64Value
                let sizeText = size.map { "\($0) bytes" } ?? "unknown size"
                lines.append("- \(filename): exists, \(sizeText), path: \(url.path)")
            } else {
                lines.append("- \(filename): missing, path: \(url.path)")
            }
        }
        return lines.joined(separator: "\n")
    }

    private static func format(error: Error, label: String, depth: Int) -> String {
        let indent = String(repeating: "  ", count: depth)
        let nsError = error as NSError
        var lines = [
            "\(indent)\(label):",
            "\(indent)- String(describing:): \(String(describing: error))",
            "\(indent)- domain: \(nsError.domain)",
            "\(indent)- code: \(nsError.code)",
            "\(indent)- localizedDescription: \(nsError.localizedDescription)"
        ]

        if nsError.userInfo.isEmpty {
            lines.append("\(indent)- userInfo: [:]")
        } else {
            lines.append("\(indent)- userInfo:")
            for key in nsError.userInfo.keys.map({ String(describing: $0) }).sorted() {
                guard let value = nsError.userInfo[key] else { continue }
                lines.append("\(indent)  - \(key): \(String(describing: value))")
                lines.append(contentsOf: nestedErrorLines(from: value, key: key, depth: depth + 2))
            }
        }

        return lines.joined(separator: "\n")
    }

    private static func nestedErrorLines(from value: Any, key: String, depth: Int) -> [String] {
        let label = key == NSUnderlyingErrorKey ? "Underlying error" : "Nested error for \(key)"
        if let error = value as? Error {
            return [format(error: error, label: label, depth: depth)]
        }
        if let errors = value as? [Error] {
            return errors.enumerated().map { index, error in
                format(error: error, label: "\(label) [\(index)]", depth: depth)
            }
        }
        if let values = value as? [Any] {
            return values.enumerated().flatMap { index, item in
                nestedErrorLines(from: item, key: "\(key)[\(index)]", depth: depth)
            }
        }
        return []
    }
}
