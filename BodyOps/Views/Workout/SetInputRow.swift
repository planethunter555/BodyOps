import SwiftUI

/// 1セット分の重量・回数入力行（ステッパー+数値入力+前回値ヒント）
struct SetInputRow: View {
    let setNumber: Int
    let previousWeight: Double?
    let previousReps: Int?
    let onUpdate: (Double, Int) -> Void

    @State private var weight: Double
    @State private var reps: Int
    @State private var weightText: String
    @State private var repsText: String

    init(setNumber: Int, weight: Double, reps: Int,
         previousWeight: Double?, previousReps: Int?,
         onUpdate: @escaping (Double, Int) -> Void) {
        self.setNumber = setNumber
        self._weight = State(initialValue: weight)
        self._reps = State(initialValue: reps)
        self._weightText = State(initialValue: weight > 0 ? Self.fmtWeight(weight) : "")
        self._repsText = State(initialValue: reps > 0 ? "\(reps)" : "")
        self.previousWeight = previousWeight
        self.previousReps = previousReps
        self.onUpdate = onUpdate
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Text("Set \(setNumber)")
                    .font(.caption.bold())
                    .foregroundStyle(.secondary)
                    .frame(width: 44, alignment: .leading)

                Spacer()

                // 重量
                HStack(spacing: 6) {
                    stepButton("minus") { stepWeight(-1) }
                    VStack(spacing: 1) {
                        TextField("0", text: $weightText)
                            .keyboardType(.decimalPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 52)
                            .onChange(of: weightText) { _, t in
                                if let v = Double(t) {
                                    weight = max(0, v)
                                    onUpdate(weight, reps)
                                }
                            }
                        Text("kg").font(.caption2).foregroundStyle(.secondary)
                    }
                    stepButton("plus") { stepWeight(1) }
                }

                Spacer()

                // レップ数
                HStack(spacing: 6) {
                    stepButton("minus") { stepReps(-1) }
                    VStack(spacing: 1) {
                        TextField("0", text: $repsText)
                            .keyboardType(.numberPad)
                            .multilineTextAlignment(.center)
                            .frame(width: 36)
                            .onChange(of: repsText) { _, t in
                                if let v = Int(t) {
                                    reps = max(0, v)
                                    onUpdate(weight, reps)
                                }
                            }
                        Text("回").font(.caption2).foregroundStyle(.secondary)
                    }
                    stepButton("plus") { stepReps(1) }
                }
            }

            if let prevW = previousWeight, let prevR = previousReps {
                Text("前回: \(Self.fmtWeight(prevW))kg × \(prevR)回")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
                    .padding(.leading, 44)
            }
        }
        .padding(.vertical, 4)
    }

    private func stepButton(_ symbol: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: 11, weight: .bold))
                .frame(width: 28, height: 28)
                .background(Color(.systemGray5))
                .clipShape(Circle())
        }
        .buttonStyle(.plain)
    }

    private func stepWeight(_ delta: Double) {
        weight = max(0, weight + delta)
        weightText = Self.fmtWeight(weight)
        onUpdate(weight, reps)
    }

    private func stepReps(_ delta: Int) {
        reps = max(0, reps + delta)
        repsText = "\(reps)"
        onUpdate(weight, reps)
    }

    private static func fmtWeight(_ w: Double) -> String {
        w.truncatingRemainder(dividingBy: 1) == 0
            ? String(format: "%.0f", w)
            : String(format: "%.1f", w)
    }
}
