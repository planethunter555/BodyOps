import Foundation
import SwiftData

/// App Store スクリーンショット撮影用のサンプルデータ投入。
/// 起動引数 `-seedScreenshotData` が渡されたときのみ実行される（本番ビルドでは無効）。
/// UIテスト（AppStoreScreenshotTests）から起動時に使用する。
enum ScreenshotSeeder {
    static var isEnabled: Bool {
        ProcessInfo.processInfo.arguments.contains("-seedScreenshotData")
    }

    static let sessionTag = "screenshot-demo-session"

    @MainActor
    static func seed(into context: ModelContext) {
        // 冪等化: 既に投入済みなら何もしない
        let existing = (try? context.fetch(FetchDescriptor<WorkoutSession>())) ?? []
        guard existing.isEmpty else { return }

        seedProfile(context)
        seedWorkouts(context)
        seedMeals(context)
        seedChat(context)
        try? context.save()

        // AIコーチのバナーを出さないためダミーのAPIキーを設定し、会話を復元させる
        try? KeychainService.shared.save(apiKey: "demo-key-for-screenshots", forProvider: .claude)
        UserDefaults.standard.set(sessionTag, forKey: "currentChatSessionTag")
    }

    // MARK: - Profile

    private static func seedProfile(_ context: ModelContext) {
        let profile = UserProfile(
            height: 172, weight: 68, bodyFatPercentage: 18,
            targetMuscleMass: 62, targetBodyFat: 13, weeklyWorkoutDays: 4,
            goals: "体脂肪を落としつつ筋量を維持。夏までに-3kg。",
            constraints: "膝に不安があるので高重量スクワットは避けたい。"
        )
        context.insert(profile)

        let setting = LLMSetting(provider: .claude, modelName: "claude-sonnet-5")
        context.insert(setting)
    }

    // MARK: - Workouts

    private static func exercise(_ name: String, _ category: String, in context: ModelContext) -> Exercise {
        let descriptor = FetchDescriptor<Exercise>(predicate: #Predicate { $0.name == name })
        if let found = try? context.fetch(descriptor).first { return found }
        let ex = Exercise(name: name, category: category, isPreset: true)
        context.insert(ex)
        return ex
    }

    private static func seedWorkouts(_ context: ModelContext) {
        let cal = Calendar.current
        let bench = exercise("ベンチプレス", "胸", in: context)
        let squat = exercise("スクワット", "脚", in: context)
        let row = exercise("ラットプルダウン", "背中", in: context)
        let shoulder = exercise("ショルダープレス", "肩", in: context)

        // ベンチプレスの右肩上がりの推移を作る（グラフ映え）
        let benchPlan: [(daysAgo: Int, weight: Double, reps: Int)] = [
            (60, 60, 8), (53, 62.5, 8), (46, 62.5, 9), (39, 65, 8),
            (32, 65, 9), (25, 67.5, 8), (18, 70, 7), (11, 70, 8), (0, 72.5, 8)
        ]

        for plan in benchPlan {
            let date = cal.date(byAdding: .day, value: -plan.daysAgo, to: Date()) ?? Date()
            let session = WorkoutSession(date: date, memo: "")
            context.insert(session)
            var vol = 0.0

            func addSets(_ ex: Exercise, _ w: Double, _ reps: Int, _ count: Int) {
                for i in 1...count {
                    let set = WorkoutSet(setNumber: i, weight: w, reps: reps, exercise: ex, session: session)
                    set.createdAt = date
                    context.insert(set)
                    vol += w * Double(reps)
                }
            }
            addSets(bench, plan.weight, plan.reps, 3)
            // 補助種目もいくつか
            if plan.daysAgo % 2 == 0 {
                addSets(row, 45, 10, 3)
                addSets(shoulder, 18, 12, 3)
            } else {
                addSets(squat, 80, 8, 3)
            }
            session.totalVolume = vol
        }
    }

    // MARK: - Meals

    private static func meal(_ context: ModelContext, type: String, desc: String,
                             kcal: Double, p: Double, f: Double, c: Double, hoursAgo: Int) {
        let record = MealRecord(mealDescription: desc, mealType: type,
                                calories: kcal, protein: p, fat: f, carbs: c)
        record.recordedAt = Calendar.current.date(byAdding: .hour, value: -hoursAgo, to: Date()) ?? Date()
        context.insert(record)
    }

    private static func seedMeals(_ context: ModelContext) {
        meal(context, type: "breakfast", desc: "オートミール、卵2個、バナナ", kcal: 420, p: 24, f: 12, c: 55, hoursAgo: 8)
        meal(context, type: "lunch", desc: "鶏胸肉200g、玄米、味噌汁、サラダ", kcal: 680, p: 52, f: 14, c: 82, hoursAgo: 4)
        meal(context, type: "snack", desc: "プロテイン、ヨーグルト", kcal: 220, p: 30, f: 5, c: 12, hoursAgo: 1)
    }

    // MARK: - Chat

    private static func seedChat(_ context: ModelContext) {
        let base = Calendar.current.date(byAdding: .minute, value: -10, to: Date()) ?? Date()
        let turns: [(role: String, content: String)] = [
            ("user", "今日の夕食、あと何をどれくらい食べたらいい？"),
            ("assistant", """
            今日はここまでで約1320kcal・P106g／F31g／C149gです。目標(2200kcal・P140/F70/C260)まで、あと880kcal・P34g・C111gほど。

            夕食のおすすめは:
            ・鮭2切れ or 鶏もも150g(タンパク質)
            ・ごはん200g＋味噌汁(炭水化物)
            ・野菜炒め(ビタミン・食物繊維)

            脂質はもう十分なので、揚げ物は避けて焼く・蒸すがおすすめです。膝の負担も考え、明日は上半身メインにしましょう。
            """),
            ("user", "ありがとう！明日のメニューも組んで")
        ]
        for (index, turn) in turns.enumerated() {
            let msg = ChatMessage(role: turn.role, content: turn.content,
                                  chatType: "workout_advice", sessionTag: sessionTag)
            msg.createdAt = Calendar.current.date(byAdding: .minute, value: index, to: base) ?? base
            context.insert(msg)
        }
    }
}
