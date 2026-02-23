import SwiftUI
import SwiftData

struct WorkoutRecordSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext
    let date: Date

    var body: some View {
        NavigationStack {
            Text("筋トレ記録")
                .navigationTitle("筋トレ記録")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("閉じる") { dismiss() }
                    }
                }
        }
    }
}
