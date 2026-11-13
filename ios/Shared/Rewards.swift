import Foundation

/// Milestone badges and the accents they unlock (shared/rewards.json; Windows: windows/ui/rewards.js).
/// Everything is worked out from synced data, so iPhone and Windows agree without storing anything extra;
/// badges already celebrated are remembered on this device so an accent never locks again.
enum Rewards {
    struct Metrics: Equatable { var completions = 0; var activeDays = 0 }

    /// completions: finished tasks (not notes) plus habit check-ins; activeDays: days with either.
    static func metrics(tasks: [(completedDay: String?, isNote: Bool)], logs: [(dayKey: String, count: Int)]) -> Metrics {
        var days = Set<String>(), completions = 0
        for task in tasks where !task.isNote { if let day = task.completedDay { completions += 1; days.insert(day) } }
        for log in logs where log.count > 0 { completions += log.count; days.insert(log.dayKey) }
        return Metrics(completions: completions, activeDays: days.count)
    }
    @MainActor static func metrics(tasks: [PlannerTask], logs: [HabitLog]) -> Metrics {
        metrics(tasks: tasks.map { (completedDay: $0.completedAt.map(PlannerLogic.plannerDay), isNote: $0.note) },
                logs: logs.map { (dayKey: $0.dayKey, count: $0.count) })
    }
    static func value(_ metrics: Metrics, _ metric: String) -> Int { metric == "activeDays" ? metrics.activeDays : metrics.completions }
    /// Badges reached, in their listed order.
    static func earned(_ metrics: Metrics) -> [String] { RewardsData.badges.filter { value(metrics, $0.metric) >= $0.goal }.map(\.id) }
    /// Accents open to choose: the free ones, then each unlocked by an earned badge.
    static func accents(earned: [String]) -> [String] {
        let have = Set(earned)
        return RewardsData.freeAccents + RewardsData.badges.filter { $0.unlocks != nil && have.contains($0.id) }.compactMap(\.unlocks)
    }
    static let allAccents = RewardsData.freeAccents + RewardsData.badges.compactMap(\.unlocks)
    static func unlockedBy(_ accent: String) -> RewardsData.Badge? { RewardsData.badges.first { $0.unlocks == accent } }

    /// Badges earned: from the data, plus any celebrated on this device before.
    static func earnedBadges(_ metrics: Metrics, defaults: UserDefaults = .standard) -> [String] {
        let stored = defaults.stringArray(forKey: "earnedBadges") ?? []
        let earned = earned(metrics)
        return earned + stored.filter { !earned.contains($0) }
    }

    /// "2 habits and 1 task left today. …" — the evening check-in's text, or nil when nothing is left.
    static func eveningText(habitsLeft: Int, tasksLeft: Int) -> String? {
        func part(_ n: Int, _ word: String) -> String? { n > 0 ? "\(n) \(word)\(n == 1 ? "" : "s")" : nil }
        let left = [part(habitsLeft, "habit"), part(tasksLeft, "task")].compactMap { $0 }.joined(separator: " and ")
        return left.isEmpty ? nil : "\(left) left today. Even one small one counts."
    }
}
