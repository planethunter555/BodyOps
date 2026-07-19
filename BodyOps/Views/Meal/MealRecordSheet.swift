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
    /// 選択された入力方式（確認画面のレイアウトが変わる）
    @State private var entryMode: MealEntryMode = .manual
    /// 一覧から「編集」で選ばれた既存の食事（実行時に編集モードへ切り替える）
    @State private var runtimeEditingMeal: MealRecord?
    /// 一覧から「削除」で選ばれた食事（確認ダイアログ用）
    @State private var mealToDelete: MealRecord?
    @State private var showAIConsent = false
    @State private var showCamera = false
    @State private var showLibraryPicker = false
    @State private var showPhotoDialog = false
    @State private var selectedPhoto: PhotosPickerItem?
    /// カメラを閉じた後に自動でAI推定を開始するためのフラグ（表示競合を避ける）
    @State private var pendingAutoEstimate = false
    @AppStorage(AIConsentStorage.key) private var hasAIConsent = false

    /// 直接編集で開かれた食事、または一覧から編集で選ばれた食事
    private var activeEditingMeal: MealRecord? { editingMeal ?? runtimeEditingMeal }
    private var isEditMode: Bool { activeEditingMeal != nil }

    var body: some View {
        NavigationStack {
            Group {
                if !isEditMode && step == .chooseMethod {
                    MealInputMethodView(
                        mealType: $viewModel.mealType,
                        onTakePhoto: {
                            entryMode = .photo
                            showCamera = true
                        },
                        onPickFromLibrary: {
                            entryMode = .photo
                            showLibraryPicker = true
                        },
                        onChooseTextAI: {
                            entryMode = .textAI
                            step = .confirm
                        },
                        onChooseManual: {
                            entryMode = .manual
                            step = .confirm
                        },
                        onEditMeal: { meal in
                            // 既存の食事を編集モードで開く（保存で上書き）
                            viewModel.load(from: meal)
                            runtimeEditingMeal = meal
                            entryMode = .manual
                            step = .confirm
                        },
                        onDeleteMeal: { meal in
                            mealToDelete = meal
                        }
                    )
                } else {
                    MealConfirmView(
                        viewModel: viewModel,
                        isEditMode: isEditMode,
                        mode: entryMode,
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
                // 直接編集で開いた場合を除き、確認画面には入力方法へ戻るボタンを出す
                if editingMeal == nil && step == .confirm {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            backToMethodSelection()
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
            .confirmationDialog(
                "この食事を削除しますか？",
                isPresented: Binding(get: { mealToDelete != nil }, set: { if !$0 { mealToDelete = nil } }),
                titleVisibility: .visible
            ) {
                Button("削除", role: .destructive) {
                    if let meal = mealToDelete { deleteMeal(meal) }
                    mealToDelete = nil
                }
                Button("キャンセル", role: .cancel) { mealToDelete = nil }
            }
        }
    }

    // MARK: - Actions

    /// 確認画面から入力方法選択へ戻る。実行時編集中なら入力内容をリセットする。
    private func backToMethodSelection() {
        if runtimeEditingMeal != nil {
            runtimeEditingMeal = nil
            viewModel.reset()
        }
        step = .chooseMethod
    }

    private func deleteMeal(_ meal: MealRecord) {
        modelContext.delete(meal)
        try? modelContext.save()
    }

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
        if let meal = activeEditingMeal {
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
