import SwiftUI
import SwiftData

struct IntakeSyncSettingsSection: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var settings: [IntakeSyncSetting]

    @State private var enabled = false
    @State private var endpointURLString = IntakeSyncSetting.defaultEndpointURLString
    @State private var token = ""
    @State private var statusMessage: String?
    @State private var isTestingConnection = false

    private var currentSetting: IntakeSyncSetting? { settings.first }

    var body: some View {
        Section {
            Toggle("learning_coachへ送信", isOn: $enabled)
            TextField("送信先URL", text: $endpointURLString)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
            SecureField("送信トークン", text: $token)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()

            if let statusMessage {
                Text(statusMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack {
                Button {
                    save(flushAfterSave: true)
                } label: {
                    Label("送信設定を保存", systemImage: "square.and.arrow.up")
                }

                Spacer()

                Button {
                    testConnection()
                } label: {
                    if isTestingConnection {
                        ProgressView()
                    } else {
                        Label("接続テスト", systemImage: "network")
                    }
                }
                .disabled(isTestingConnection)
            }
        } header: {
            Text("からだ連携")
        } footer: {
            Text("筋トレ・食事を保存したときに Mac mini の /intake/bodyops へ直接送信します。失敗した記録は端末に残し、起動時や設定保存時に再送します。")
        }
        .onAppear(perform: load)
    }

    private func load() {
        if let setting = currentSetting {
            enabled = setting.enabled
            endpointURLString = setting.endpointURLString
        }
        token = KeychainService.shared.loadIntakeToken() ?? ""
    }

    private func save(flushAfterSave: Bool) {
        let setting: IntakeSyncSetting
        if let existing = currentSetting {
            setting = existing
        } else {
            setting = IntakeSyncSetting()
            modelContext.insert(setting)
        }

        setting.enabled = enabled
        let trimmedURL = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        setting.endpointURLString = trimmedURL.isEmpty ? IntakeSyncSetting.defaultEndpointURLString : trimmedURL
        endpointURLString = setting.endpointURLString
        setting.updatedAt = Date()

        do {
            try KeychainService.shared.saveIntakeToken(token.trimmingCharacters(in: .whitespacesAndNewlines))
            try modelContext.save()
            statusMessage = "送信設定を保存しました"
            if flushAfterSave {
                Task { @MainActor in
                    await IntakeSyncService(context: modelContext).flushPending()
                }
            }
        } catch {
            statusMessage = "送信設定の保存に失敗しました"
        }
    }

    private func testConnection() {
        save(flushAfterSave: false)
        guard statusMessage != "送信設定の保存に失敗しました" else { return }
        isTestingConnection = true
        statusMessage = "接続を確認しています…"
        Task { @MainActor in
            defer { isTestingConnection = false }
            do {
                try await IntakeSyncService(context: modelContext).testConnection()
                statusMessage = "接続テストに成功しました"
            } catch {
                statusMessage = "接続テストに失敗しました"
            }
        }
    }
}
