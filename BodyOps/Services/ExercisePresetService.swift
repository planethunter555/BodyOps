import Foundation
import SwiftData

struct ExercisePresetEntry: Decodable {
    let name: String
    let category: String
}

final class ExercisePresetService {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    func seedIfNeeded() throws {
        let count = try context.fetchCount(FetchDescriptor<Exercise>(
            predicate: #Predicate { $0.isPreset }
        ))
        guard count == 0 else { return }

        let entries = try loadPresets()
        for entry in entries {
            let exercise = Exercise(name: entry.name, category: entry.category, isPreset: true)
            context.insert(exercise)
        }
        try context.save()
    }

    private func loadPresets() throws -> [ExercisePresetEntry] {
        guard let url = Bundle.main.url(forResource: "ExercisePresets", withExtension: "json") else {
            throw ExercisePresetError.fileNotFound
        }
        let data = try Data(contentsOf: url)
        return try JSONDecoder().decode([ExercisePresetEntry].self, from: data)
    }
}

enum ExercisePresetError: Error {
    case fileNotFound
}
