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

    /// プリセット種目をシードする。
    /// - 新規プリセットはDBに追加する。
    /// - 既存種目でカテゴリが「その他」のものは正しいカテゴリに更新する。
    func seedIfNeeded() throws {
        let entries = try loadPresets()
        var changed = false

        for entry in entries {
            let name = entry.name
            let descriptor = FetchDescriptor<Exercise>(
                predicate: #Predicate { $0.name == name }
            )
            if let existing = try context.fetch(descriptor).first {
                if existing.category == "その他" {
                    existing.category = entry.category
                    changed = true
                }
            } else {
                context.insert(Exercise(name: entry.name, category: entry.category, isPreset: true))
                changed = true
            }
        }

        if changed {
            try context.save()
        }
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
