import Foundation
import SwiftData

enum LLMSettingsStore {
    static func current(in context: ModelContext) throws -> LLMSetting {
        let settings = try fetchAll(in: context)
        if let current = settings.first {
            deleteDuplicates(in: context, keeping: current, from: settings)
            let migrated = migrateRetiredModelIfNeeded(current)
            if settings.count > 1 || migrated {
                try context.save()
            }
            return current
        }

        let setting = LLMSetting()
        context.insert(setting)
        try context.save()
        return setting
    }

    /// 保存済みモデル名が廃止済みIDの場合、現行モデルへ移行する
    @discardableResult
    private static func migrateRetiredModelIfNeeded(_ setting: LLMSetting) -> Bool {
        guard setting.provider == .claude,
              let replacement = LLMProvider.migratedClaudeModel(for: setting.modelName) else {
            return false
        }
        setting.modelName = replacement
        setting.updatedAt = Date()
        return true
    }

    static func currentIfExists(in context: ModelContext) -> LLMSetting? {
        guard let settings = try? fetchAll(in: context),
              let current = settings.first else { return nil }
        deleteDuplicates(in: context, keeping: current, from: settings)
        try? context.save()
        return current
    }

    private static func fetchAll(in context: ModelContext) throws -> [LLMSetting] {
        let descriptor = FetchDescriptor<LLMSetting>(
            sortBy: [SortDescriptor(\.updatedAt, order: .reverse)]
        )
        return try context.fetch(descriptor)
    }

    private static func deleteDuplicates(in context: ModelContext, keeping retained: LLMSetting, from settings: [LLMSetting]) {
        for setting in settings where setting.id != retained.id {
            context.delete(setting)
        }
    }
}
