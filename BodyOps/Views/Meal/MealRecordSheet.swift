import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Meal Type

private enum MealType: String, CaseIterable {
    case breakfast
    case lunch
    case dinner
    case snack

    var label: String {
        switch self {
        case .breakfast: return "朝"
        case .lunch: return "昼"
        case .dinner: return "夜"
        case .snack: return "間食"
        }
    }
}


// MARK: - Sheet

struct MealRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let date: Date

    @State private var viewModel = MealRecordViewModel()
    @State private var showPhotoSourceSheet = false

    var body: some View {
        NavigationStack {
            Form {
                mealTypeSection
                descriptionSection
                photoSection
                estimationSection
                pfcSection
            }
            .navigationTitle("食事記録")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("閉じる") { dismiss() }
                }
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        viewModel.save(date: date, context: modelContext)
                        dismiss()
                    }
                    .disabled(!viewModel.canSave)
                }
            }
            .sheet(isPresented: $showPhotoSourceSheet) {
                PhotoSourceSheet { data in
                    viewModel.imageData = data
                }
            }
        }
    }

    // MARK: - Sections

    private var mealTypeSection: some View {
        Section("食事タイプ") {
            Picker("種別", selection: $viewModel.mealType) {
                ForEach(MealType.allCases, id: \.rawValue) { type in
                    Text(type.label).tag(type.rawValue)
                }
            }
            .pickerStyle(.segmented)
        }
    }

    private var descriptionSection: some View {
        Section("食事内容") {
            TextField("例: ご飯1杯、鶏胸肉200g、味噌汁", text: $viewModel.mealDescription, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    private var photoSection: some View {
        Section("写真（任意）") {
            Button {
                showPhotoSourceSheet = true
            } label: {
                Label(
                    viewModel.imageData == nil ? "写真を追加" : "写真を変更",
                    systemImage: "photo.on.rectangle"
                )
            }

            if let img = viewModel.previewImage {
                HStack {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Button(role: .destructive) {
                        viewModel.imageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    private var estimationSection: some View {
        Section {
            Button {
                Task { await viewModel.estimatePFC(context: modelContext) }
            } label: {
                if viewModel.isEstimating {
                    HStack {
                        ProgressView().scaleEffect(0.8)
                        Text("AI推定中...")
                    }
                } else {
                    Label("AIでPFCを推定", systemImage: "brain")
                }
            }
            .disabled(viewModel.cannotEstimate)

            if let error = viewModel.estimationError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
            if viewModel.estimationSucceeded {
                Label("推定完了。値を確認・修正してください。", systemImage: "checkmark.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.green)
            }
        } header: {
            Text("AI推定")
        } footer: {
            Text("食事内容または写真からカロリー・PFCを自動推定します")
        }
    }

    private var pfcSection: some View {
        Section("栄養素（手動修正可）") {
            pfcRow(label: "カロリー (kcal)", value: $viewModel.calories)
            pfcRow(label: "タンパク質 P (g)", value: $viewModel.protein)
            pfcRow(label: "脂質 F (g)", value: $viewModel.fat)
            pfcRow(label: "炭水化物 C (g)", value: $viewModel.carbs)
        }
    }

    private func pfcRow(label: String, value: Binding<Double>) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .multilineTextAlignment(.trailing)
                .frame(width: 80)
        }
    }
}

// MARK: - ViewModel

@Observable
@MainActor
final class MealRecordViewModel {
    var mealDescription: String = ""
    var mealType: String = MealType.lunch.rawValue
    var imageData: Data?
    var calories: Double = 0
    var protein: Double = 0
    var fat: Double = 0
    var carbs: Double = 0
    var isEstimating = false
    var estimationError: String?
    var estimationSucceeded = false

    var previewImage: UIImage? {
        guard let data = imageData else { return nil }
        return UIImage(data: data)
    }

    var cannotEstimate: Bool {
        let empty = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return isEstimating || (empty && imageData == nil)
    }

    var canSave: Bool {
        let hasNutrition = calories > 0 || protein > 0 || fat > 0 || carbs > 0
        let hasDescription = !mealDescription.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        return hasNutrition || hasDescription
    }

    func estimatePFC(context: ModelContext) async {
        let trimmed = mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty || imageData != nil else { return }

        let setting = fetchLLMSetting(context: context)
        let apiKey = KeychainService.shared.load(forProvider: setting.provider) ?? ""
        guard !apiKey.isEmpty else {
            estimationError = "APIキーが設定されていません。設定タブで入力してください。"
            return
        }

        isEstimating = true
        estimationError = nil
        estimationSucceeded = false
        defer { isEstimating = false }

        let messages = [LLMMessage(role: "user", content: buildPrompt(description: trimmed), imageData: imageData)]
        let system = "栄養の専門家として、必ずJSONのみで返答してください。説明やmarkdownは不要です。"

        var fullResponse = ""
        do {
            for try await chunk in LLMAPIService().sendMessage(
                messages: messages,
                system: system,
                provider: setting.provider,
                apiKey: apiKey,
                modelName: setting.modelName
            ) {
                fullResponse += chunk
            }
            parseAndApply(response: fullResponse)
        } catch {
            estimationError = "AI推定に失敗しました。手動で入力してください。"
        }
    }

    func save(date: Date, context: ModelContext) {
        let record = MealRecord(
            mealDescription: mealDescription,
            mealType: mealType,
            calories: calories,
            protein: protein,
            fat: fat,
            carbs: carbs
        )
        record.imageData = imageData
        record.recordedAt = resolvedDate(for: date)
        context.insert(record)
        try? context.save()
    }

    // MARK: - Private

    private func fetchLLMSetting(context: ModelContext) -> LLMSetting {
        let descriptor = FetchDescriptor<LLMSetting>()
        return (try? context.fetch(descriptor).first) ?? LLMSetting()
    }

    private func buildPrompt(description: String) -> String {
        var parts = ["以下の食事のカロリーとPFCを推定してください。"]
        if !description.isEmpty { parts.append("食事内容: \(description)") }
        if imageData != nil { parts.append("（添付の食事写真も参考にしてください）") }
        parts.append("JSON形式のみで返答: {\"calories\": 数値, \"protein\": 数値, \"fat\": 数値, \"carbs\": 数値}")
        return parts.joined(separator: "\n")
    }

    private func parseAndApply(response: String) {
        let cleaned = response
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        guard let start = cleaned.firstIndex(of: "{"),
              let end = cleaned.lastIndex(of: "}") else {
            estimationError = "JSONの解析に失敗しました。手動で入力してください。"
            return
        }
        let jsonString = String(cleaned[start...end])
        guard let data = jsonString.data(using: .utf8),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            estimationError = "JSONの解析に失敗しました。手動で入力してください。"
            return
        }
        calories = numericValue(json["calories"])
        protein = numericValue(json["protein"])
        fat = numericValue(json["fat"])
        carbs = numericValue(json["carbs"])
        estimationSucceeded = true
    }

    private func numericValue(_ value: Any?) -> Double {
        if let val = value as? Double { return val }
        if let val = value as? Int { return Double(val) }
        return 0
    }

    private func resolvedDate(for date: Date) -> Date {
        Calendar.current.isDateInToday(date) ? Date() : date
    }
}

// MARK: - Photo Source Sheet

private struct PhotoSourceSheet: View {
    let onImagePicked: (Data) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var showingCamera = false

    var body: some View {
        if showingCamera {
            // カメラ全画面。撮影 or キャンセルでシートが閉じる
            CameraPickerView { image in
                if let data = image.jpegData(compressionQuality: 1.0) {
                    onImagePicked(ImageCompressor.compress(data))
                }
            }
            .ignoresSafeArea()
        } else {
            // ライブラリ。ナビバーにトグル付き
            PhotoLibraryPicker(
                onPick: { jpeg in
                    onImagePicked(ImageCompressor.compress(jpeg))
                    dismiss()
                },
                onCancel: { dismiss() },
                onSwitchToCamera: { showingCamera = true }
            )
            .ignoresSafeArea()
        }
    }
}

// MARK: - Photo Library Picker

private struct PhotoLibraryPicker: UIViewControllerRepresentable {
    let onPick: (Data) -> Void
    let onCancel: () -> Void
    let onSwitchToCamera: () -> Void

    func makeUIViewController(context: Context) -> UINavigationController {
        var config = PHPickerConfiguration()
        config.filter = .images
        config.selectionLimit = 1
        let picker = PHPickerViewController(configuration: config)
        picker.delegate = context.coordinator

        // ナビバーのタイトル部分にライブラリ｜カメラのトグルを配置
        let seg = UISegmentedControl(items: ["ライブラリ", "カメラ"])
        seg.selectedSegmentIndex = 0
        seg.addTarget(
            context.coordinator,
            action: #selector(Coordinator.segmentChanged(_:)),
            for: .valueChanged
        )
        picker.navigationItem.titleView = seg

        return UINavigationController(rootViewController: picker)
    }

    func updateUIViewController(_ uiViewController: UINavigationController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, PHPickerViewControllerDelegate {
        let parent: PhotoLibraryPicker
        init(_ parent: PhotoLibraryPicker) { self.parent = parent }

        @objc func segmentChanged(_ seg: UISegmentedControl) {
            if seg.selectedSegmentIndex == 1 {
                parent.onSwitchToCamera()
            }
        }

        func picker(_ picker: PHPickerViewController, didFinishPicking results: [PHPickerResult]) {
            // Cancel タップ時は results が空 → シートを閉じる
            guard let result = results.first else {
                DispatchQueue.main.async { self.parent.onCancel() }
                return
            }
            let onPick = parent.onPick
            result.itemProvider.loadObject(ofClass: UIImage.self) { object, _ in
                guard let image = object as? UIImage,
                      let jpeg = image.jpegData(compressionQuality: 1.0) else { return }
                DispatchQueue.main.async { onPick(jpeg) }
            }
        }
    }
}

// MARK: - Camera Picker

import UIKit

struct CameraPickerView: UIViewControllerRepresentable {
    let onCapture: (UIImage) -> Void
    @Environment(\.dismiss) private var dismiss

    func makeUIViewController(context: Context) -> UIImagePickerController {
        let picker = UIImagePickerController()
        picker.sourceType = .camera
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ uiViewController: UIImagePickerController, context: Context) {}

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    final class Coordinator: NSObject, UIImagePickerControllerDelegate, UINavigationControllerDelegate {
        let parent: CameraPickerView

        init(_ parent: CameraPickerView) { self.parent = parent }

        func imagePickerController(_ picker: UIImagePickerController,
                                   didFinishPickingMediaWithInfo info: [UIImagePickerController.InfoKey: Any]) {
            if let image = info[.originalImage] as? UIImage {
                parent.onCapture(image)
            }
            parent.dismiss()
        }

        func imagePickerControllerDidCancel(_ picker: UIImagePickerController) {
            parent.dismiss()
        }
    }
}
