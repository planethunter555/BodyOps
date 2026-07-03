import SwiftUI
import SwiftData
import PhotosUI

struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ChatViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotosPicker = false
    @State private var showAIConsent = false
    @State private var showSessionList = false
    @AppStorage(AIConsentStorage.key) private var hasAIConsent = false
    @FocusState private var isInputFocused: Bool

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                if !viewModel.hasAPIKey {
                    apiKeyBanner
                } else {
                    messageList
                    Divider()
                    inputBar
                }
            }
            .navigationTitle("AIアドバイス")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.startNewChat()
                    } label: {
                        Label("新しい会話", systemImage: "square.and.pencil")
                    }
                }
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        showSessionList = true
                    } label: {
                        Label("会話履歴", systemImage: "clock.arrow.circlepath")
                    }
                }
            }
            .sheet(isPresented: $showSessionList) {
                ChatSessionListView(
                    currentTag: viewModel.currentSessionTag,
                    summaries: viewModel.sessionSummaries(),
                    onSelect: { tag in viewModel.loadSession(tag: tag) },
                    onDelete: { tag in viewModel.deleteSession(tag: tag) }
                )
            }
            .onAppear {
                viewModel.setup(context: modelContext)
                viewModel.refreshConfigurationState()
            }
            .onChange(of: selectedPhoto) { _, item in
                loadPhoto(item)
            }
            .sheet(isPresented: $showAIConsent) {
                AIConsentSheet(providerName: viewModel.currentProviderDescription) {
                    hasAIConsent = true
                    showAIConsent = false
                    viewModel.send()
                } onCancel: {
                    showAIConsent = false
                }
            }
        }
    }

    // MARK: - API Key Banner

    private var apiKeyBanner: some View {
        VStack(spacing: 16) {
            Image(systemName: "key.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
            Text("APIキーが設定されていません")
                .font(.headline)
            Text("設定タブでLLMプロバイダーとAPIキーを設定してください。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    // MARK: - Message List

    private var messageList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 12) {
                    AIHealthNoticeView()
                    if viewModel.messages.isEmpty {
                        welcomeMessage
                    }
                    ForEach(viewModel.messages) { bubble in
                        ChatBubbleView(bubble: bubble)
                            .id(bubble.id)
                    }
                    if showsProgressIndicator {
                        StreamPhaseIndicatorView(phase: viewModel.streamPhase)
                    }
                }
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.messages.last?.content) { _, _ in
                scrollToBottom(proxy: proxy)
            }
            .onChange(of: viewModel.messages.last?.thinking) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    private var welcomeMessage: some View {
        VStack(spacing: 8) {
            Image(systemName: "brain")
                .font(.system(size: 40))
                .foregroundStyle(.blue)
                .padding(.top, 32)
            Text("Body Ops AI")
                .font(.headline)
            Text("筋トレ・食事についてなんでも相談してください。\nトレーニング記録や目標を考慮してアドバイスします。")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
            Text(viewModel.currentModelDescription)
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .padding(.top, 4)
            Text("入力内容・添付画像・プロフィール・目標・直近の筋トレ/食事記録を、設定中のAIプロバイダーへ送信します。")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 24)
                .padding(.top, 2)
        }
        .padding(.bottom, 16)
    }

    /// 最初のテキストが届くまで進行状況インジケータを表示する
    private var showsProgressIndicator: Bool {
        guard viewModel.isLoading, let last = viewModel.messages.last else { return false }
        return !last.isUser && last.content.isEmpty
    }

    // MARK: - Input Bar

    private var inputBar: some View {
        VStack(spacing: 0) {
            if let imageData = viewModel.pendingImageData,
               let uiImage = UIImage(data: imageData) {
                pendingImagePreview(uiImage: uiImage)
            }
            HStack(alignment: .bottom, spacing: 8) {
                PhotosPicker(selection: $selectedPhoto, matching: .images) {
                    Image(systemName: "camera.fill")
                        .font(.system(size: 20))
                        .foregroundStyle(.secondary)
                        .frame(width: 36, height: 36)
                }

                TextField("メッセージを入力...", text: $viewModel.inputText, axis: .vertical)
                    .lineLimit(1...5)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                    .focused($isInputFocused)

                if viewModel.isLoading {
                    // ストリーミング中は停止ボタンに切り替え
                    Button {
                        viewModel.stopStreaming()
                    } label: {
                        Image(systemName: "stop.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(.red)
                    }
                } else {
                    Button {
                        isInputFocused = false
                        if hasAIConsent {
                            viewModel.send()
                        } else {
                            showAIConsent = true
                        }
                    } label: {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 32))
                            .foregroundStyle(canSend ? .blue : .gray)
                    }
                    .disabled(!canSend)
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
        }
    }

    private func pendingImagePreview(uiImage: UIImage) -> some View {
        HStack {
            Image(uiImage: uiImage)
                .resizable()
                .scaledToFill()
                .frame(width: 60, height: 60)
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Spacer()
            Button {
                viewModel.pendingImageData = nil
                selectedPhoto = nil
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 8)
    }

    // MARK: - Helpers

    private var canSend: Bool {
        !viewModel.inputText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        || viewModel.pendingImageData != nil
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        if let last = viewModel.messages.last {
            withAnimation(.easeOut(duration: 0.2)) {
                proxy.scrollTo(last.id, anchor: .bottom)
            }
        }
    }

    private func loadPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let compressed = ImageCompressor.compress(data)
                await MainActor.run {
                    viewModel.pendingImageData = compressed
                }
            }
        }
    }
}

// MARK: - Stream Phase Indicator

/// ストリーミングの進行状況（接続中→考え中）を経過秒数つきで表示するインジケータ
struct StreamPhaseIndicatorView: View {
    let phase: ChatStreamPhase
    @State private var animating = false
    @State private var startDate = Date()

    private var phaseLabel: String {
        switch phase {
        case .connecting: return "接続中…"
        case .thinking: return "考え中…"
        default: return "応答を生成中…"
        }
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            Circle()
                .fill(Color(.systemGray4))
                .frame(width: 28, height: 28)
                .overlay {
                    Image(systemName: "brain")
                        .font(.system(size: 14))
                        .foregroundStyle(.secondary)
                }
            HStack(spacing: 6) {
                HStack(spacing: 4) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(Color(.systemGray3))
                            .frame(width: 6, height: 6)
                            .scaleEffect(animating ? 1.0 : 0.5)
                            .opacity(animating ? 1.0 : 0.3)
                            .animation(
                                .easeInOut(duration: 0.5)
                                    .repeatForever(autoreverses: true)
                                    .delay(Double(index) * 0.15),
                                value: animating
                            )
                    }
                }
                Text(phaseLabel)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                TimelineView(.periodic(from: startDate, by: 1)) { context in
                    let elapsed = Int(context.date.timeIntervalSince(startDate))
                    if elapsed >= 3 {
                        Text("\(elapsed)秒")
                            .font(.caption2)
                            .foregroundStyle(.tertiary)
                            .monospacedDigit()
                    }
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
        .onAppear {
            animating = true
            startDate = Date()
        }
    }
}

// MARK: - Chat Bubble View

struct ChatBubbleView: View {
    let bubble: ChatBubbleItem
    @State private var thinkingExpanded = false

    var body: some View {
        HStack(alignment: .bottom, spacing: 8) {
            if bubble.isUser {
                Spacer(minLength: 60)
                bubbleContent
            } else {
                avatarIcon
                bubbleContent
                Spacer(minLength: 60)
            }
        }
    }

    /// 思考中はライブ表示、回答が届いたら折りたたみに切り替える
    @ViewBuilder
    private var thinkingSection: some View {
        if let thinking = bubble.thinking, !thinking.isEmpty {
            if bubble.content.isEmpty {
                // 回答がまだ無い間は思考をライブ表示（何をしているか見える安心感）
                VStack(alignment: .leading, spacing: 4) {
                    Label("考え中…", systemImage: "brain")
                        .font(.caption.bold())
                        .foregroundStyle(.secondary)
                    Text(thinking)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.tertiary)
                        .lineLimit(6)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color(.systemGray6).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            } else {
                DisclosureGroup(isExpanded: $thinkingExpanded) {
                    Text(thinking)
                        .font(.caption)
                        .italic()
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.top, 4)
                } label: {
                    Label("思考の過程", systemImage: "brain")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.systemGray6).opacity(0.6))
                .clipShape(RoundedRectangle(cornerRadius: 12))
            }
        }
    }

    private var avatarIcon: some View {
        Circle()
            .fill(Color.blue.opacity(0.15))
            .frame(width: 28, height: 28)
            .overlay {
                Image(systemName: "brain")
                    .font(.system(size: 14))
                    .foregroundStyle(.blue)
            }
    }

    private var bubbleContent: some View {
        VStack(alignment: bubble.isUser ? .trailing : .leading, spacing: 4) {
            thinkingSection
            if let imageData = bubble.imageData, let uiImage = UIImage(data: imageData) {
                Image(uiImage: uiImage)
                    .resizable()
                    .scaledToFit()
                    .frame(maxWidth: 200)
                    .clipShape(RoundedRectangle(cornerRadius: 12))
            }
            if !bubble.content.isEmpty {
                Text(bubble.content)
                    .font(.body)
                    .foregroundStyle(bubble.isUser ? .white : .primary)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(bubble.isUser ? Color.blue : Color(.systemGray6))
                    .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
            }
        }
    }
}
