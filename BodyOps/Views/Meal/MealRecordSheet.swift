import SwiftUI
import SwiftData

struct MealRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let date: Date

    var body: some View {
        NavigationStack {
            Text("食事記録")
                .navigationTitle("食事記録")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { dismiss() }
                    }
                }
        }
    }
}
