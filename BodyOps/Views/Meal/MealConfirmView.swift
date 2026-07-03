import SwiftUI

/// 食事記録の確認・保存画面（Step 2）。
/// 推定ステータスバナーと下部固定の保存ボタンで「AI結果はまだ保存されていない」ことを明示する。
struct MealConfirmView: View {
    @Bindable var viewModel: MealRecordViewModel
    let isEditMode: Bool
    let onRequestEstimate: () -> Void
    let onChangePhoto: () -> Void
    let onSave: () -> Void

    var body: some View {
        Form {
            mealTypeSection
            descriptionSection
            photoSection
            estimationSection
            pfcSection
        }
        .safeAreaInset(edge: .bottom) {
            saveButton
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
        Section("写真") {
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
                Text("食事内容または写真からカロリー・PFCを自動推定します")
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
            onRequestEstimate()
        } label: {
            Label(title, systemImage: "brain")
                .font(.subheadline)
        }
        .disabled(viewModel.cannotEstimate)
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

    private var saveButton: some View {
        Button {
            onSave()
        } label: {
            Label(isEditMode ? "変更を保存" : "この内容で保存", systemImage: "checkmark.circle.fill")
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
        }
        .buttonStyle(.borderedProminent)
        .tint(.green)
        .disabled(!viewModel.canSave || viewModel.isEstimating)
        .padding()
        .background(.bar)
    }
}
