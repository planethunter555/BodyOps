import Foundation
import SwiftData

final class WorkoutCopyService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func copyPreviousSession() throws -> [WorkoutSet]? {
        var descriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        descriptor.fetchLimit = 1
        guard let lastSession = try context.fetch(descriptor).first else {
            return nil
        }
        let originalSets = lastSession.sets.sorted { $0.setNumber < $1.setNumber }
        guard !originalSets.isEmpty else { return nil }
        return originalSets.map { original in
            WorkoutSet(
                setNumber: original.setNumber,
                weight: original.weight,
                reps: original.reps,
                exercise: original.exercise,
                session: nil
            )
        }
    }

    func copyLastSet(from existingSet: WorkoutSet, newSetNumber: Int) -> WorkoutSet {
        WorkoutSet(
            setNumber: newSetNumber,
            weight: existingSet.weight,
            reps: existingSet.reps,
            exercise: existingSet.exercise,
            session: existingSet.session
        )
    }
}
