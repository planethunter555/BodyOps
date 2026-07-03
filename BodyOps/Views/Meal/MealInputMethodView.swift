import SwiftUI
import UIKit

/// 食事記録の入力方法選択画面（Step 1）。
/// 「写真で記録」「テキストで記録」の2つの導線と手動入力リンクを提供する。
struct MealInputMethodView: View {
    @Binding var mealType: String
    let onTakePhoto: () -> Void
    let onPickFromLibrary: () -> Void
    let onChooseText: () -> Void
    let onChooseManual: () -> Void

    @State private var showPhotoDialog = false

    private var cameraAvailable: Bool {
        UIImagePickerController.isSourceTypeAvailable(.camera)
    }

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                Picker("食事タイプ", selection: $mealType) {
                    ForEach(MealType.allCases, id: \.rawValue) { type in
                        Text(type.label).tag(type.rawValue)
                    }
                }
                .pickerStyle(.segmented)
                .padding(.bottom, 4)

                methodCard(
                    icon: "camera.fill",
                    title: "写真で記録",
                    description: "食事の写真からAIがカロリー・PFCを自動推定します"
                ) {
                    if cameraAvailable {
                        showPhotoDialog = true
                    } else {
                        onPickFromLibrary()
                    }
                }

                methodCard(
                    icon: "keyboard",
                    title: "テキストで記録",
                    description: "「ご飯1杯、鶏胸肉200g」のように入力してAIで推定します"
                ) {
                    onChooseText()
                }

                Button("AIを使わず手動で入力する") {
                    onChooseManual()
                }
                .font(.subheadline)
                .padding(.top, 8)

                Spacer(minLength: 0)
            }
            .padding()
        }
        .background(Color(.systemGroupedBackground))
        .confirmationDialog("写真で記録", isPresented: $showPhotoDialog) {
            Button("カメラで撮影") { onTakePhoto() }
            Button("ライブラリから選択") { onPickFromLibrary() }
            Button("キャンセル", role: .cancel) {}
        }
    }

    private func methodCard(icon: String, title: String, description: String,
                            action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 14) {
                Image(systemName: icon)
                    .font(.title2)
                    .foregroundStyle(Color.green)
                    .frame(width: 44, height: 44)
                    .background(Color.green.opacity(0.12))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.leading)
                }
                Spacer()
                Image(systemName: "chevron.right")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color(.secondarySystemGroupedBackground))
            .clipShape(RoundedRectangle(cornerRadius: 14))
        }
        .buttonStyle(.plain)
    }
}
