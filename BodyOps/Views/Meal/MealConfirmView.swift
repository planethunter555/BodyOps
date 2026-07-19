import SwiftUI

/// 食事記録の入力・確認画面（Step 2）。
/// 入力方式（写真AI/テキストAI/手動）によってレイアウトが変わり、
/// 手動モードではAI関連のUIを一切表示しない。
struct MealConfirmView: View {
    private enum Field: Hashable {
        case description
        case calories
        case protein
        case fat
        case carbs
    }

    @Bindable var viewModel: MealRecordViewModel
    let isEditMode: Bool
    let mode: MealEntryMode
    let onRequestEstimate: () -> Void
    let onChangePhoto: () -> Void
    let onSave: () -> Void

    @FocusState private var focusedField: Field?

    var body: some View {
        Form {
            mealTypeSection

            if isEditMode {
                descriptionSection(header: "食事内容")
                photoSection(header: "写真")
                estimationSection
                pfcSection(header: "栄養素（手動修正可）")
            } else {
                switch mode {
                case .photo:
                    photoSection(header: "写真")
                    estimationSection
                    pfcSection(header: "推定結果（修正できます）")
                    descriptionSection(header: "メモ（任意）")
                case .textAI:
                    descriptionSection(header: "食事内容")
                    estimationSection
                    pfcSection(header: "推定結果（修正できます）")
                case .manual:
                    pfcSection(header: "栄養素を入力")
                    descriptionSection(header: "メモ（任意）")
                    photoSection(header: "写真（任意）")
                }
            }
        }
        .scrollDismissesKeyboard(.interactively)
        .toolbar {
            // 数値キーボードにはリターンキーが無いため「完了」を用意する。
            // 「クリア」は編集中の欄をワンタップで空にする（削除の手間対策）
            ToolbarItemGroup(placement: .keyboard) {
                Button("クリア") { clearFocusedField() }
                Spacer()
                Button("完了") { focusedField = nil }
            }
        }
        .safeAreaInset(edge: .bottom) {
            saveArea
        }
    }

    /// AIモード（写真/テキスト）では、推定を実行するまで保存できないようにする。
    /// 推定に失敗した場合や、栄養素を手で入力済みの場合は保存を許可する。
    private var needsEstimationBeforeSave: Bool {
        guard !isEditMode, mode == .textAI || mode == .photo else { return false }
        return !viewModel.estimationAttempted && !viewModel.hasNutritionInput
    }

    private func clearFocusedField() {
        switch focusedField {
        case .description: viewModel.mealDescription = ""
        case .calories: viewModel.calories = 0
        case .protein: viewModel.protein = 0
        case .fat: viewModel.fat = 0
        case .carbs: viewModel.carbs = 0
        case nil: break
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

    private func descriptionSection(header: String) -> some View {
        Section {
            TextField("例: ご飯1杯、鶏胸肉200g、味噌汁", text: $viewModel.mealDescription, axis: .vertical)
                .lineLimit(3...6)
                .focused($focusedField, equals: .description)
        } header: {
            Text(header)
        } footer: {
            if !isEditMode && mode == .textAI {
                Text("入力した内容をAIが解析してカロリー・PFCを推定します")
            }
        }
    }

    private func photoSection(header: String) -> some View {
        Section(header) {
            if let img = viewModel.previewImage {
                HStack {
                    Image(uiImage: img)
                        .resizable()
                        .scaledToFill()
                        .frame(width: 72, height: 72)
                        .clipShape(RoundedRectangle(cornerRadius: 8))
                    Spacer()
                    Button("変更") { onChangePhoto() }
                        .font(.caption)
                        .buttonStyle(.bordered)
                    Button(role: .destructive) {
                        viewModel.imageData = nil
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                            .foregroundStyle(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            } else {
                Button {
                    onChangePhoto()
                } label: {
                    Label("写真を追加", systemImage: "photo.on.rectangle")
                }
            }
        }
    }

    @ViewBuilder
    private var estimationSection: some View {
        Section {
            switch viewModel.estimationPhase {
            case .estimating:
                HStack(spacing: 10) {
                    ProgressView()
                    Text("AIが解析しています…")
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            case .done:
                estimationResultView
            case .failed(let message):
                VStack(alignment: .leading, spacing: 6) {
                    Label(message, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.red)
                    estimateButton(title: "もう一度AIで推定")
                }
            case .idle:
                estimateButton(title: isEditMode ? "AIで再推定" : "AIで栄養を推定")
            }
        } header: {
            Text("AI推定")
        } footer: {
            if case .idle = viewModel.estimationPhase {
                Text(mode == .photo
                     ? "写真からカロリー・PFCを自動推定します"
                     : "食事内容からカロリー・PFCを自動推定します")
            }
        }
    }

    private var estimationResultView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("推定完了 — 内容を確認してください", systemImage: "checkmark.circle.fill")
                .font(.caption.bold())
                .foregroundStyle(.green)

            if let details = viewModel.estimationDetails {
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
                }
            }

            estimateButton(title: "もう一度AIで推定")
        }
    }

    private func estimateButton(title: String) -> some View {
        Button {
            focusedField = nil
            onRequestEstimate()
        } label: {
            Label(title, systemImage: "brain")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 2)
        }
        .buttonStyle(.borderedProminent)
        .disabled(viewModel.cannotEstimate)
        .listRowInsets(EdgeInsets(top: 6, leading: 16, bottom: 6, trailing: 16))
    }

    private func pfcSection(header: String) -> some View {
        Section(header) {
            pfcRow(label: "カロリー", unit: "kcal", value: $viewModel.calories, field: .calories)
            pfcRow(label: "タンパク質 P", unit: "g", value: $viewModel.protein, field: .protein)
            pfcRow(label: "脂質 F", unit: "g", value: $viewModel.fat, field: .fat)
            pfcRow(label: "炭水化物 C", unit: "g", value: $viewModel.carbs, field: .carbs)
        }
    }

    private func pfcRow(label: String, unit: String, value: Binding<Double>, field: Field) -> some View {
        HStack {
            Text(label)
            Spacer()
            TextField("0", value: value, format: .number)
                .keyboardType(.decimalPad)
                .focused($focusedField, equals: field)
                .multilineTextAlignment(.trailing)
                .frame(width: 100)
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
                .background(Color(.systemGray6))
                .clipShape(RoundedRectangle(cornerRadius: 8))
            Text(unit)
                .font(.caption)
                .foregroundStyle(.secondary)
                .frame(width: 34, alignment: .leading)
        }
        .contentShape(Rectangle())
        .onTapGesture { focusedField = field }
    }

    private var saveArea: some View {
        VStack(spacing: 6) {
            if needsEstimationBeforeSave && viewModel.canSave {
                Text("先に「AIで栄養を推定」を実行してください")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Button {
                focusedField = nil
                onSave()
            } label: {
                Label(isEditMode ? "変更を保存" : "この内容で保存", systemImage: "checkmark.circle.fill")
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 6)
            }
            .buttonStyle(.borderedProminent)
            .tint(.green)
            .disabled(!viewModel.canSave || viewModel.isEstimating || needsEstimationBeforeSave)
        }
        .padding()
        .background(.bar)
    }
}
