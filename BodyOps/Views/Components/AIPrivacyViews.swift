import SwiftUI

enum AIConsentStorage {
    static let key = "aiDataSharingConsentAccepted"
}

struct AIConsentSheet: View {
    let providerName: String
    let onAgree: () -> Void
    let onCancel: () -> Void

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    Label("AI機能で送信される情報", systemImage: "brain.head.profile")
                        .font(.headline)

                    Text("AIアドバイスや食事推定を利用すると、以下の情報が選択中のAIプロバイダーへ送信される場合があります。")
                        .foregroundStyle(.secondary)

                    consentList([
                        "入力したメッセージ",
                        "添付画像または食事写真",
                        "プロフィール（身長・体重・体脂肪率など）",
                        "目標・制約・要望",
                        "直近の筋トレ記録",
                        "直近の食事記録"
                    ])

                    VStack(alignment: .leading, spacing: 8) {
                        Text("送信先")
                            .font(.subheadline.bold())
                        Text("現在選択中のAIプロバイダー: \(providerName)")
                        Text("Claude (Anthropic)、ChatGPT (OpenAI)、Gemini (Google) のうち、設定画面で選択したプロバイダーへ送信されます。")
                            .foregroundStyle(.secondary)
                    }

                    VStack(alignment: .leading, spacing: 8) {
                        Text("APIキーと通常記録")
                            .font(.subheadline.bold())
                        Text("APIキーは端末内のiOS Keychainに保存され、開発者のサーバーには保存されません。")
                        Text("同意しない場合、AI機能は利用できませんが、筋トレ・食事・体重などの通常記録は利用できます。")
                            .foregroundStyle(.secondary)
                        Text("同意は設定画面からいつでも解除できます。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .padding()
            }
            .navigationTitle("AIデータ送信の同意")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("キャンセル") { onCancel() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("同意して今後は表示しない") { onAgree() }
                }
            }
        }
    }

    private func consentList(_ items: [String]) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(items, id: \.self) { item in
                Label(item, systemImage: "checkmark.circle")
                    .font(.subheadline)
            }
        }
    }
}

struct AIHealthNoticeView: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Label("AIアドバイスについて", systemImage: "exclamationmark.triangle")
                .font(.subheadline.bold())
                .foregroundStyle(.orange)

            Text("このAIアドバイスは、医療・診断・治療を目的としたものではなく、記録内容をもとにした一般的な運動・栄養のヒントです。痛み、疾患、治療、服薬、体調不良に関する判断は、医師などの専門家に相談してください。")
                .font(.caption)
                .foregroundStyle(.secondary)

            Text("一般的な運動・栄養情報については、以下の公的資料も参考にしてください。")
                .font(.caption)
                .foregroundStyle(.secondary)

            VStack(alignment: .leading, spacing: 6) {
                Link("厚生労働省 身体活動・運動の推進", destination: URL(string: "https://www.mhlw.go.jp/stf/seisakunitsuite/bunya/kenkou_iryou/kenkou/undou/index.html")!)
                Link("厚生労働省 日本人の食事摂取基準", destination: URL(string: "https://www.mhlw.go.jp/stf/newpage_44138.html")!)
                Link("WHO Physical activity", destination: URL(string: "https://www.who.int/news-room/fact-sheets/detail/physical-activity")!)
            }
            .font(.caption)
        }
        .padding(14)
        .background(Color(.secondarySystemGroupedBackground))
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }
}
