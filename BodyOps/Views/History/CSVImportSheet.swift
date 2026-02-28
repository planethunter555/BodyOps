import SwiftUI
import SwiftData

struct CSVImportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    @State private var showFilePicker = false
    @State private var parsedSessions: [CSVWorkoutSession] = []
    @State private var parseError: String?
    @State private var importResult: String?
    @State private var isImported = false

    var body: some View {
        NavigationStack {
            Group {
                if isImported {
                    resultView
                } else if !parsedSessions.isEmpty {
                    previewView
                } else {
                    instructionView
                }
            }
            .navigationTitle("CSVインポート")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
            }
        }
        .fileImporter(
            isPresented: $showFilePicker,
            allowedContentTypes: [.commaSeparatedText, .plainText],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
    }

    // MARK: - Instruction

    private var instructionView: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                VStack(alignment: .leading, spacing: 8) {
                    Label("CSVフォーマット", systemImage: "doc.text")
                        .font(.headline)
                    Text("以下の形式のCSVファイルを用意してください：")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    Text("date,exercise_name,set_number,weight_kg,reps,session_memo")
                        .font(.system(.caption, design: .monospaced))
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("サンプル", systemImage: "list.bullet")
                        .font(.subheadline.bold())
                    Text(sampleCSV)
                        .font(.system(.caption2, design: .monospaced))
                        .padding(8)
                        .background(Color(.systemGray6))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                VStack(alignment: .leading, spacing: 4) {
                    Label("ルール", systemImage: "info.circle")
                        .font(.subheadline.bold())
                    ForEach(rules, id: \.self) { rule in
                        Text("• \(rule)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                if let error = parseError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                        .padding(8)
                        .background(Color.red.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                Button {
                    parseError = nil
                    showFilePicker = true
                } label: {
                    Label("CSVファイルを選択", systemImage: "folder")
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                }
                .buttonStyle(.borderedProminent)
            }
            .padding()
        }
    }

    // MARK: - Preview

    private var previewView: some View {
        VStack(spacing: 0) {
            List {
                Section("インポート予定 \(parsedSessions.count)セッション") {
                    ForEach(parsedSessions, id: \.date) { session in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(formatDate(session.date))
                                .font(.subheadline.bold())
                            ForEach(session.exercises, id: \.name) { exercise in
                                Text("  \(exercise.name)  \(exercise.sets.count)セット")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            if !session.memo.isEmpty {
                                Text("  メモ: \(session.memo)")
                                    .font(.caption2)
                                    .foregroundStyle(.tertiary)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
            Divider()
            HStack(spacing: 12) {
                Button("やり直す") {
                    parsedSessions = []
                    parseError = nil
                }
                .buttonStyle(.bordered)
                .frame(maxWidth: .infinity)

                Button("インポート") {
                    performImport()
                }
                .buttonStyle(.borderedProminent)
                .frame(maxWidth: .infinity)
            }
            .padding()
        }
    }

    // MARK: - Result

    private var resultView: some View {
        VStack(spacing: 20) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 60))
                .foregroundStyle(.green)
            Text(importResult ?? "インポート完了")
                .font(.headline)
                .multilineTextAlignment(.center)
            Button("閉じる") { dismiss() }
                .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Actions

    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first else { return }
            guard url.startAccessingSecurityScopedResource() else {
                parseError = "ファイルへのアクセス権限がありません"
                return
            }
            defer { url.stopAccessingSecurityScopedResource() }
            do {
                let text = try String(contentsOf: url, encoding: .utf8)
                parsedSessions = try WorkoutCSVImporter.parse(csvText: text)
                parseError = nil
            } catch let err as WorkoutCSVImporter.ImportError {
                parseError = err.localizedDescription
            } catch {
                parseError = "ファイル読み込みエラー: \(error.localizedDescription)"
            }
        case .failure(let error):
            parseError = "ファイル選択エラー: \(error.localizedDescription)"
        }
    }

    private func performImport() {
        let result = WorkoutCSVImporter.save(sessions: parsedSessions, context: modelContext)
        importResult = "\(result.imported)セッションをインポートしました"
        if result.skipped > 0 {
            importResult! += "\n（\(result.skipped)セッションは既存のため skipped）"
        }
        isImported = true
    }

    // MARK: - Helpers

    private func formatDate(_ date: Date) -> String {
        let fmt = DateFormatter()
        fmt.dateFormat = "yyyy年M月d日(E)"
        fmt.locale = Locale(identifier: "ja_JP")
        return fmt.string(from: date)
    }

    private let sampleCSV = """
date,exercise_name,set_number,weight_kg,reps,session_memo
2024-01-15,ベンチプレス,1,80.0,10,胸の日
2024-01-15,ベンチプレス,2,80.0,8,
2024-01-15,ダンベルフライ,1,20.0,12,
2024-01-16,スクワット,1,100.0,10,脚の日
"""

    private let rules = [
        "同じ日付の行が1セッションにまとまります",
        "session_memoは日付ごとの最初の非空値を使用",
        "同じ日付のセッションが既にある場合はスキップ",
        "種目名が既存と一致しない場合は新規作成"
    ]
}
