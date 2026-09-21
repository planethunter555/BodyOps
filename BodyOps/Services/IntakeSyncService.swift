import Foundation
import SwiftData

enum IntakeKind: String, Codable, Sendable {
    case workout
    case meal
}

enum IntakeJSONValue: Codable, Equatable, Sendable {
    case string(String)
    case int(Int)
    case double(Double)
    case bool(Bool)
    case array([IntakeJSONValue])
    case object([String: IntakeJSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .null
        } else if let value = try? container.decode(Bool.self) {
            self = .bool(value)
        } else if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else if let value = try? container.decode(Double.self) {
            self = .double(value)
        } else if let value = try? container.decode(String.self) {
            self = .string(value)
        } else if let value = try? container.decode([IntakeJSONValue].self) {
            self = .array(value)
        } else {
            self = .object(try container.decode([String: IntakeJSONValue].self))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .int(let value): try container.encode(value)
        case .double(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct BodyOpsIntakeRequest: Codable, Equatable, Sendable {
    let kind: IntakeKind
    let externalID: String?
    let occurredAt: String?
    let title: String?
    let durationMinutes: Int?
    let caloriesKcal: Double?
    let proteinG: Double?
    let fatG: Double?
    let carbsG: Double?
    let payload: [String: IntakeJSONValue]

    enum CodingKeys: String, CodingKey {
        case kind
        case externalID = "external_id"
        case occurredAt = "occurred_at"
        case title
        case durationMinutes = "duration_minutes"
        case caloriesKcal = "calories_kcal"
        case proteinG = "protein_g"
        case fatG = "fat_g"
        case carbsG = "carbs_g"
        case payload
    }
}

struct IntakeSyncResponse: Decodable, Sendable {
    let ok: Bool?
    let kind: String?
    let inserted: Bool?
}

@MainActor
final class IntakeSyncService {
    private let context: ModelContext
    private let session: URLSessionProtocol
    private let now: () -> Date

    init(
        context: ModelContext,
        session: URLSessionProtocol = URLSession.shared,
        now: @escaping () -> Date = { Date() }
    ) {
        self.context = context
        self.session = session
        self.now = now
    }

    @discardableResult
    func enqueue(session workoutSession: WorkoutSession, sets explicitSets: [WorkoutSet]? = nil) throws -> IntakeOutboxItem? {
        guard isConfigured else { return nil }
        let request = makeWorkoutRequest(session: workoutSession, sets: explicitSets)
        return try enqueue(request: request)
    }

    @discardableResult
    func enqueue(meal: MealRecord) throws -> IntakeOutboxItem? {
        guard isConfigured else { return nil }
        let request = makeMealRequest(meal: meal)
        return try enqueue(request: request)
    }

    func flushPending(limit: Int = 20) async {
        guard let setting = currentSetting(),
              setting.enabled,
              let endpointURL = setting.endpointURL,
              let token = KeychainService.shared.loadIntakeToken(),
              !token.isEmpty else { return }

        let dueItems = pendingItems(limit: limit)
        for item in dueItems {
            await send(item: item, endpointURL: endpointURL, token: token)
        }
    }

    func testConnection() async throws {
        guard let setting = currentSetting(),
              setting.enabled,
              let endpointURL = setting.endpointURL,
              let token = KeychainService.shared.loadIntakeToken(),
              !token.isEmpty else {
            throw IntakeSyncError.notConfigured
        }
        let request = BodyOpsIntakeRequest(
            kind: .workout,
            externalID: "bodyops-connection-test-\(UUID().uuidString)",
            occurredAt: Self.formatOccurredAt(now()),
            title: "BodyOps connection test",
            durationMinutes: nil,
            caloriesKcal: nil,
            proteinG: nil,
            fatG: nil,
            carbsG: nil,
            payload: ["test": .bool(true)]
        )
        try await post(payloadData: try encoder.encode(request), endpointURL: endpointURL, token: token)
    }

    private var isConfigured: Bool {
        guard let setting = currentSetting(),
              setting.enabled,
              setting.endpointURL != nil,
              let token = KeychainService.shared.loadIntakeToken(),
              !token.isEmpty else { return false }
        return true
    }

    private func currentSetting() -> IntakeSyncSetting? {
        let descriptor = FetchDescriptor<IntakeSyncSetting>()
        return try? context.fetch(descriptor).first
    }

    private func enqueue(request: BodyOpsIntakeRequest) throws -> IntakeOutboxItem {
        let eventID = request.externalID ?? UUID().uuidString
        let payloadData = try encoder.encode(request)
        let descriptor = FetchDescriptor<IntakeOutboxItem>(
            predicate: #Predicate { $0.eventID == eventID }
        )
        if let existing = try context.fetch(descriptor).first {
            existing.payloadData = payloadData
            existing.kind = request.kind.rawValue
            existing.nextAttemptAt = now()
            existing.lastError = nil
            try context.save()
            return existing
        }

        let item = IntakeOutboxItem(
            eventID: eventID,
            kind: request.kind.rawValue,
            payloadData: payloadData,
            createdAt: now(),
            nextAttemptAt: now()
        )
        context.insert(item)
        try context.save()
        return item
    }

    private func pendingItems(limit: Int) -> [IntakeOutboxItem] {
        let date = now()
        var descriptor = FetchDescriptor<IntakeOutboxItem>(
            predicate: #Predicate { $0.nextAttemptAt <= date },
            sortBy: [SortDescriptor(\IntakeOutboxItem.createdAt)]
        )
        descriptor.fetchLimit = limit
        return (try? context.fetch(descriptor)) ?? []
    }

    private func send(item: IntakeOutboxItem, endpointURL: URL, token: String) async {
        item.lastAttemptAt = now()
        do {
            try await post(payloadData: item.payloadData, endpointURL: endpointURL, token: token)
            context.delete(item)
            try context.save()
        } catch {
            item.attemptCount += 1
            item.lastError = error.localizedDescription
            item.nextAttemptAt = now().addingTimeInterval(backoffDelay(after: item.attemptCount))
            try? context.save()
        }
    }

    private func post(payloadData: Data, endpointURL: URL, token: String) async throws {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(token, forHTTPHeaderField: "X-Intake-Token")
        request.httpBody = payloadData

        let (_, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse,
              (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw IntakeSyncError.serverStatus(status)
        }
    }

    private func backoffDelay(after attemptCount: Int) -> TimeInterval {
        let exponent = min(max(attemptCount - 1, 0), 6)
        let seconds = 60 * pow(2.0, Double(exponent))
        return min(seconds, 60 * 60)
    }

    private func makeWorkoutRequest(session: WorkoutSession, sets explicitSets: [WorkoutSet]?) -> BodyOpsIntakeRequest {
        let sets = explicitSets ?? session.sets
        let grouped = Dictionary(grouping: sets) { set in
            set.exercise?.id.uuidString ?? "unknown"
        }
        let exerciseValues = grouped.values.map { groupedSets -> IntakeJSONValue in
            let sortedSets = groupedSets.sorted { $0.setNumber < $1.setNumber }
            let exercise = sortedSets.first?.exercise
            let setValues: [IntakeJSONValue] = sortedSets.map { set in
                .object([
                    "set_id": .string(set.id.uuidString),
                    "set_number": .int(set.setNumber),
                    "weight": .double(set.weight),
                    "reps": .int(set.reps),
                    "volume": .double(set.volume),
                    "created_at": .string(Self.formatOccurredAt(set.createdAt))
                ])
            }
            return .object([
                "exercise_id": .string(exercise?.id.uuidString ?? ""),
                "exercise_name": .string(exercise?.name ?? ""),
                "category": .string(exercise?.category ?? ""),
                "sets": .array(setValues)
            ])
        }
        .sorted { lhs, rhs in
            lhs.sortKey < rhs.sortKey
        }

        let minutes = Calendar.current.dateComponents([.minute], from: session.date, to: now()).minute
        return BodyOpsIntakeRequest(
            kind: .workout,
            externalID: "bodyops-workout-\(session.id.uuidString)",
            occurredAt: Self.formatOccurredAt(session.date),
            title: workoutTitle(for: sets),
            durationMinutes: minutes.map { max($0, 0) },
            caloriesKcal: nil,
            proteinG: nil,
            fatG: nil,
            carbsG: nil,
            payload: [
                "session_id": .string(session.id.uuidString),
                "memo": .string(session.memo),
                "total_volume": .double(session.totalVolume),
                "exercises": .array(exerciseValues)
            ]
        )
    }

    private func makeMealRequest(meal: MealRecord) -> BodyOpsIntakeRequest {
        BodyOpsIntakeRequest(
            kind: .meal,
            externalID: "bodyops-meal-\(meal.id.uuidString)",
            occurredAt: Self.formatOccurredAt(meal.recordedAt),
            title: mealTitle(for: meal),
            durationMinutes: nil,
            caloriesKcal: meal.calories,
            proteinG: meal.protein,
            fatG: meal.fat,
            carbsG: meal.carbs,
            payload: [
                "meal_id": .string(meal.id.uuidString),
                "meal_type": .string(meal.mealType),
                "description": .string(meal.mealDescription)
            ]
        )
    }

    private func workoutTitle(for sets: [WorkoutSet]) -> String? {
        let names = Array(Set(sets.compactMap { $0.exercise?.name })).sorted()
        guard !names.isEmpty else { return "筋トレ" }
        return names.prefix(3).joined(separator: "、")
    }

    private func mealTitle(for meal: MealRecord) -> String {
        let trimmed = meal.mealDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? meal.mealType : trimmed
    }

    private var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.withoutEscapingSlashes, .sortedKeys]
        return encoder
    }

    static func formatOccurredAt(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd HH:mm:ss"
        return formatter.string(from: date)
    }
}

private extension IntakeJSONValue {
    var sortKey: String {
        guard case .object(let object) = self else { return "" }
        guard case .string(let name) = object["exercise_name"] else { return "" }
        return name
    }
}

enum IntakeSyncError: LocalizedError {
    case notConfigured
    case serverStatus(Int)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "からだ連携が設定されていません"
        case .serverStatus(let status):
            return "Intake server returned status \(status)"
        }
    }
}
