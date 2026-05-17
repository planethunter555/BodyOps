import SwiftUI
import SwiftData
import PhotosUI

// MARK: - Models

struct EstimationItem {
    let name: String
    let amount: String
    let calories: Double
    let protein: Double
    let fat: Double
    let carbs: Double
}

struct EstimationDetails {
    let items: [EstimationItem]
    let summary: String?
}

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
    var editingMeal: MealRecord? = nil

    @State private var viewModel = MealRecordViewModel()
    @State private var showPhotoSourceSheet = false
    @State private var showAIConsent = false
    @AppStorage(AIConsentStorage.key) private var hasAIConsent = false

    private var isEditMode: Bool { editingMeal != nil }

    var body: some View {
        NavigationStack {
            Form {
                mealTypeSection
                descriptionSection
                photoSection
                if !isEditMode { estimationSection }
                pfcSection
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
                ToolbarItem(placement: .primaryAction) {
                    Button("保存") {
                        if let meal = editingMeal {
                            viewModel.update(meal: meal, context: modelContext)
                        } else {
                            viewModel.save(date: date, context: modelContext)
                        }
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
            .sheet(isPresented: $showAIConsent) {
                AIConsentSheet(providerName: viewModel.currentProviderDescription(context: modelContext)) {
                    hasAIConsent = true
                    showAIConsent = false
                    Task { await viewModel.estimatePFC(context: modelContext) }
                } onCancel: {
                    showAIConsent = false
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
                if hasAIConsent {
                    Task { await viewModel.estimatePFC(context: modelContext) }
                } else {
                    showAIConsent = true
                }
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
            if let details = viewModel.estimationDetails {
                VStack(alignment: .leading, spacing: 8) {
                    Label("推定完了。値を確認・修正してください。", systemImage: "checkmark.circle.fill")
                        .font(.caption)
                        .foregroundStyle(.green)

                    if !details.items.isEmpty {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("推定内訳：")
                                .font(.caption2)
                                .foregroundStyle(.secondary)

                            ForEach(details.items, id: \.name) { item in
                                HStack(spacing: 4) {
                                    Text("• \(item.name)")
                                        .font(.caption2)
                                    Text("(\(item.amount))")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                    Spacer()
                                    Text("P:\(Int(item.protein))g F:\(Int(item.fat))g C:\(Int(item.carbs))g")
                                        .font(.caption2)
                                        .foregroundStyle(.secondary)
                                }
                            }
                        }
                        .padding(.vertical, 4)
                    }

                    if let summary = details.summary, !summary.isEmpty {
                        Text(summary)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                            .padding(.top, 2)
                    }
                }
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
    var estimationDetails: EstimationDetails?

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

        do {
            // stream: false の非ストリーミングリクエストで1回確実に取得する
            let result = try await LLMAPIService().sendOnce(
                messages: messages,
                system: system,
                provider: setting.provider,
                apiKey: apiKey,
                modelName: setting.modelName
            )
            parseAndApply(response: result.text)
            // API使用量を記録
            let record = APIUsageRecord(
                provider: setting.provider.rawValue,
                modelName: setting.modelName,
                inputTokens: result.inputTokens,
                outputTokens: result.outputTokens
            )
            context.insert(record)
            try? context.save()
        } catch {
            estimationError = "AI推定に失敗しました。手動で入力してください。"
        }
    }

    func currentProviderDescription(context: ModelContext) -> String {
        fetchLLMSetting(context: context).provider.displayName
    }

    func load(from meal: MealRecord) {
        mealDescription = meal.mealDescription
        mealType = meal.mealType
        imageData = meal.imageData
        calories = meal.calories
        protein = meal.protein
        fat = meal.fat
        carbs = meal.carbs
    }

    func update(meal: MealRecord, context: ModelContext) {
        meal.mealDescription = mealDescription
        meal.mealType = mealType
        meal.imageData = imageData
        meal.calories = calories
        meal.protein = protein
        meal.fat = fat
        meal.carbs = carbs
        try? context.save()
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
        parts.append("""
        JSON形式のみで返答してください:
        {
          "total": {
            "calories": 数値,
            "protein": 数値,
            "fat": 数値,
            "carbs": 数値
          },
          "items": [
            {
              "name": "食材名",
              "amount": "分量",
              "calories": 数値,
              "protein": 数値,
              "fat": 数値,
              "carbs": 数値
            }
          ],
          "summary": "簡単な説明（1文）"
        }
        """)
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

        // 新形式を試す
        if let total = json["total"] as? [String: Any] {
            calories = numericValue(total["calories"])
            protein = numericValue(total["protein"])
            fat = numericValue(total["fat"])
            carbs = numericValue(total["carbs"])

            var items: [EstimationItem] = []
            if let itemsArray = json["items"] as? [[String: Any]] {
                for itemDict in itemsArray {
                    let item = EstimationItem(
                        name: itemDict["name"] as? String ?? "",
                        amount: itemDict["amount"] as? String ?? "",
                        calories: numericValue(itemDict["calories"]),
                        protein: numericValue(itemDict["protein"]),
                        fat: numericValue(itemDict["fat"]),
                        carbs: numericValue(itemDict["carbs"])
                    )
                    items.append(item)
                }
            }

            let summary = json["summary"] as? String
            estimationDetails = EstimationDetails(items: items, summary: summary)
            estimationSucceeded = true
        } else {
            // 旧形式（後方互換性）
            calories = numericValue(json["calories"])
            protein = numericValue(json["protein"])
            fat = numericValue(json["fat"])
            carbs = numericValue(json["carbs"])
            estimationDetails = EstimationDetails(items: [], summary: nil)
            estimationSucceeded = true
        }
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
                if let data = ImageCompressor.compress(image) {
                    onImagePicked(data)
                }
            }
            .ignoresSafeArea()
        } else {
            // ライブラリ。ナビバーにトグル付き
            PhotoLibraryPicker(
                onPick: { jpeg in
                    onImagePicked(jpeg)
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
        let cameraAvailable = UIImagePickerController.isSourceTypeAvailable(.camera)
        let seg = UISegmentedControl(items: cameraAvailable ? ["ライブラリ", "カメラ"] : ["ライブラリ"])
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
                      let jpeg = ImageCompressor.compress(image) else { return }
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
        picker.sourceType = UIImagePickerController.isSourceTypeAvailable(.camera) ? .camera : .photoLibrary
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
