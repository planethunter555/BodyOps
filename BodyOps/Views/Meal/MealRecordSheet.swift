import SwiftUI
import SwiftData
import PhotosUI

/// 食事記録シート。
/// 新規作成時は「入力方法の選択 → 確認・保存」の2ステップで案内する。
struct MealRecordSheet: View {
    private enum Step {
        case chooseMethod
        case confirm
    }

    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let date: Date
    var editingMeal: MealRecord? = nil

    @State private var viewModel = MealRecordViewModel()
    @State private var step: Step = .chooseMethod
    @State private var showAIConsent = false
    @State private var showCamera = false
    @State private var showLibraryPicker = false
    @State private var showPhotoDialog = false
    @State private var selectedPhoto: PhotosPickerItem?
    /// カメラを閉じた後に自動でAI推定を開始するためのフラグ（表示競合を避ける）
    @State private var pendingAutoEstimate = false
    @AppStorage(AIConsentStorage.key) private var hasAIConsent = false

    private var isEditMode: Bool { editingMeal != nil }

    var body: some View {
        NavigationStack {
            Group {
                if !isEditMode && step == .chooseMethod {
                    MealInputMethodView(
                        mealType: $viewModel.mealType,
                        onTakePhoto: { showCamera = true },
                        onPickFromLibrary: { showLibraryPicker = true },
                        onChooseText: { step = .confirm },
                        onCopyMeal: { meal in
                            // 過去の食事を内容ごとコピーして確認画面へ（日付は記録対象日のまま）
                            viewModel.load(from: meal)
                            step = .confirm
                        }
                    )
                } else {
                    MealConfirmView(
                        viewModel: viewModel,
                        isEditMode: isEditMode,
                        onRequestEstimate: requestEstimate,
                        onChangePhoto: changePhoto,
                        onSave: save
                    )
                }
            }
            .navigationTitle(isEditMode ? "食事を編集" : "食事記録")
            .navigationBarTitleDisplayMode(.inline)
            .onAppear {
                if let meal = editingMeal {
                    viewModel.load(from: meal)
                }
            }
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                if !isEditMode && step == .confirm {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            step = .chooseMethod
                        } label: {
                            Label("入力方法", systemImage: "chevron.backward")
                        }
                    }
                }
            }
            .photosPicker(isPresented: $showLibraryPicker, selection: $selectedPhoto, matching: .images)
            .fullScreenCover(isPresented: $showCamera, onDismiss: cameraDismissed) {
                CameraPickerView { image in
                    if let data = ImageCompressor.compress(image) {
                        viewModel.imageData = data
                        step = .confirm
                        pendingAutoEstimate = true
                    }
                }
                .ignoresSafeArea()
            }
            .onChange(of: selectedPhoto) { _, item in
                loadLibraryPhoto(item)
            }
            .confirmationDialog("写真を変更", isPresented: $showPhotoDialog) {
                if UIImagePickerController.isSourceTypeAvailable(.camera) {
                    Button("カメラで撮影") { showCamera = true }
                }
                Button("ライブラリから選択") { showLibraryPicker = true }
                Button("キャンセル", role: .cancel) {}
            }
            .sheet(isPresented: $showAIConsent) {
                AIConsentSheet(
                    providerName: viewModel.currentProviderDescription(context: modelContext),
                    isOnDevice: viewModel.isOnDeviceProvider(context: modelContext)
                ) {
                    hasAIConsent = true
                    showAIConsent = false
                    Task { await viewModel.estimatePFC(context: modelContext) }
                } onCancel: {
                    showAIConsent = false
                }
            }
        }
    }

    // MARK: - Actions

    /// カメラ全画面が閉じてからAI推定を開始する（シート表示の競合を避ける）
    private func cameraDismissed() {
        guard pendingAutoEstimate else { return }
        pendingAutoEstimate = false
        requestEstimate()
    }

    private func requestEstimate() {
        guard !viewModel.cannotEstimate else { return }
        if hasAIConsent {
            Task { await viewModel.estimatePFC(context: modelContext) }
        } else {
            showAIConsent = true
        }
    }

    private func changePhoto() {
        showPhotoDialog = true
    }

    private func save() {
        if let meal = editingMeal {
            viewModel.update(meal: meal, context: modelContext)
        } else {
            viewModel.save(date: date, context: modelContext)
        }
        dismiss()
    }

    private func loadLibraryPhoto(_ item: PhotosPickerItem?) {
        guard let item else { return }
        Task {
            if let data = try? await item.loadTransferable(type: Data.self) {
                let compressed = ImageCompressor.compress(data)
                await MainActor.run {
                    selectedPhoto = nil
                    viewModel.imageData = compressed
                    step = .confirm
                    requestEstimate()
                }
            }
        }
    }
}
