import SwiftUI
import SwiftData
import PhotosUI

struct AIChatView: View {
    @Environment(\.modelContext) private var modelContext
    @State private var viewModel = ChatViewModel()
    @State private var selectedPhoto: PhotosPickerItem?
    @State private var showPhotosPicker = false
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
            }
            .onAppear {
                viewModel.setup(context: modelContext)
            }
            .onChange(of: selectedPhoto) { _, item in
                loadPhoto(item)
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
                    if viewModel.messages.isEmpty {
                        welcomeMessage
                    }
                    ForEach(viewModel.messages) { bubble in
                        ChatBubbleView(bubble: bubble)
                            .id(bubble.id)
                    }
                    if viewModel.isLoading && viewModel.messages.last?.role == "user" {
                        typingIndicator
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
        }
        .padding(.bottom, 16)
    }

    private var typingIndicator: some View {
        TypingIndicatorView()
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

                Button {
                    isInputFocused = false
                    Task { await viewModel.sendMessage() }
                } label: {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.system(size: 32))
                        .foregroundStyle(canSend ? .blue : .gray)
                }
                .disabled(!canSend || viewModel.isLoading)
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

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var animating = false

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
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color(.systemGray3))
                        .frame(width: 8, height: 8)
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
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(Color(.systemGray6))
            .clipShape(RoundedRectangle(cornerRadius: 16))
            Spacer()
        }
        .onAppear { animating = true }
    }
}

// MARK: - Chat Bubble View

struct ChatBubbleView: View {
    let bubble: ChatBubbleItem

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
