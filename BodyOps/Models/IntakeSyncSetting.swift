import Foundation
import SwiftData

@Model
final class IntakeSyncSetting {
    static let defaultEndpointURLString = "https://miwamac-mini.tail393181.ts.net/learn/intake/bodyops"

    var id: UUID
    var enabled: Bool
    var endpointURLString: String
    var updatedAt: Date

    init(enabled: Bool = false, endpointURLString: String = IntakeSyncSetting.defaultEndpointURLString) {
        self.id = UUID()
        self.enabled = enabled
        self.endpointURLString = endpointURLString
        self.updatedAt = Date()
    }

    var endpointURL: URL? {
        let trimmed = endpointURLString.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        return URL(string: trimmed)
    }
}
