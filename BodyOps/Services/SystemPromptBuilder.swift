import Foundation
import SwiftData

/// AIシステムプロンプトを組み立てるサービス。
/// ChatViewModelから分離し、単独でテスト可能にする。
struct SystemPromptBuilder {
    private let context: ModelContext

    init(context: ModelContext) {
        self.context = context
    }

    // MARK: - Public: Full Prompt

    func build() -> String {
        let profile = fetchProfile()
        var parts: [String] = []

        // ユーザー設定のPre-fixプロンプト
        if let prefix = profile?.systemPromptPrefix, !prefix.isEmpty {
            parts.append(prefix)
        }

        // ベースロール定義
        parts.append("""
        あなたは「Body Ops」専属のパーソナルトレーナー兼栄養士です。ユーザーの記録に基づき、一般的な運動・栄養・生活習慣のヒントを日本語で提供してください。

        ## 安全性と医療助言に関する制約
        - 医療診断、治療方針、服薬、疾患、怪我、痛みへの個別判断は行わない
        - 痛み、疾患、怪我、体調不良、治療、服薬に関する相談が含まれる場合は、医師などの専門家へ相談するよう促す
        - 危険な減量、極端な食事制限、過度な運動、体調悪化につながる行動を勧めない
        - 断定的な表現を避け、一般的なフィットネス・栄養情報として説明する
        """)

        // プロファイル
        if let prof = profile {
            parts.append(buildProfileSection(prof))
        }

        // トレーニング記録
        let workoutSection = buildWorkoutSection()
        if !workoutSection.isEmpty {
            parts.append(workoutSection)
        }

        // 食事記録
        let mealSection = buildMealSection()
        if !mealSection.isEmpty {
            parts.append(mealSection)
        }

        // ルール
        parts.append("## ルール\n- 具体的な数値（重量・セット数・回数・PFC）を含める\n- 制約事項を必ず考慮する\n- 怪我リスクや体調不良につながる可能性がある場合は専門家相談を促す\n- 回答は日本語で400字以内")

        return parts.joined(separator: "\n\n")
    }

    // MARK: - Public: Sections (for testing and debug)

    func buildWorkoutSection() -> String {
        var sessionDescriptor = FetchDescriptor<WorkoutSession>(
            sortBy: [SortDescriptor(\.date, order: .reverse)]
        )
        sessionDescriptor.fetchLimit = 10
        let sessions = (try? context.fetch(sessionDescriptor)) ?? []
        guard !sessions.isEmpty else { return "" }

        var lines: [String] = ["## トレーニング記録（直近\(sessions.count)セッション）"]

        for session in sessions {
            let sets = loadSets(for: session)
            guard !sets.isEmpty else { continue }

            let dateStr = formatDate(session.date)
            let grouped = Dictionary(grouping: sets) { $0.exercise?.name ?? "不明" }
            let exerciseText = grouped.sorted { $0.key < $1.key }.map { name, exerciseSets in
                let setDesc = exerciseSets.sorted { $0.setNumber < $1.setNumber }
                    .map { "\($0.weight)kg×\($0.reps)回" }
                    .joined(separator: ", ")
                return "  - \(name): \(setDesc)"
            }.joined(separator: "\n")

            lines.append("【\(dateStr)】 総ボリューム: \(Int(session.totalVolume))kg")
            lines.append(exerciseText)
            if !session.memo.isEmpty {
                lines.append("  メモ: \(session.memo)")
            }
        }

        return lines.joined(separator: "\n")
    }

    func buildMealSection() -> String {
        let twoDaysAgo = Calendar.current.date(byAdding: .day, value: -2, to: Date()) ?? Date()
        let descriptor = FetchDescriptor<MealRecord>(
            predicate: #Predicate { $0.recordedAt >= twoDaysAgo },
            sortBy: [SortDescriptor(\.recordedAt, order: .reverse)]
        )
        let meals = (try? context.fetch(descriptor)) ?? []
        guard !meals.isEmpty else { return "" }

        var lines: [String] = ["## 食事記録（直近2日）"]
        for meal in meals {
            let entry = "- \(meal.mealType)（\(formatDate(meal.recordedAt))）: " +
                "\(Int(meal.calories))kcal, P\(Int(meal.protein))g F\(Int(meal.fat))g C\(Int(meal.carbs))g"
            lines.append(entry)
        }
        return lines.joined(separator: "\n")
    }

    // MARK: - Private

    /// session.sets のlazy loadingを試み、空の場合はWorkoutSetを直接フェッチする
    func loadSets(for session: WorkoutSession) -> [WorkoutSet] {
        let direct = session.sets.sorted { $0.setNumber < $1.setNumber }
        if !direct.isEmpty { return direct }

        let sessionId = session.id
        let descriptor = FetchDescriptor<WorkoutSet>(
            predicate: #Predicate { $0.session?.id == sessionId },
            sortBy: [SortDescriptor(\.setNumber)]
        )
        return (try? context.fetch(descriptor)) ?? []
    }

    private func buildProfileSection(_ prof: UserProfile) -> String {
        var parts = ["""
        ## ユーザープロファイル
        - 身長: \(prof.height)cm / 体重: \(prof.weight)kg / 体脂肪率: \(prof.bodyFatPercentage)%
        - 目標筋肉量: \(prof.targetMuscleMass)kg / 目標体脂肪率: \(prof.targetBodyFat)%
        - 週のトレーニング可能日数: \(prof.weeklyWorkoutDays)日
        """]
        if !prof.goals.isEmpty { parts.append("## 目標\n\(prof.goals)") }
        if !prof.constraints.isEmpty { parts.append("## 制約・要望\n\(prof.constraints)") }
        return parts.joined(separator: "\n\n")
    }

    private func fetchProfile() -> UserProfile? {
        try? context.fetch(FetchDescriptor<UserProfile>()).first
    }

    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "M月d日"
        formatter.locale = Locale(identifier: "ja_JP")
        return formatter.string(from: date)
    }
}
