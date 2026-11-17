import Foundation
import SwiftData

/// Suggestions are conservative and never change a task without the user's choice, except where the
/// user has taught it: start & finish learned from similar earlier tasks, or a rule word.
enum TaskProgress {
    static func suggests(_ title: String) -> Bool {
        let words = title.lowercased().components(separatedBy: CharacterSet.alphanumerics.inverted).filter { !$0.isEmpty }
        let text = " " + words.joined(separator: " ") + " "
        if ["buy", "shop", "fold", "put away", "unload", "empty", "clean", "repair"].contains(where: { text.hasPrefix(" " + $0 + " ") }) { return false }
        return ["laundry", "dishwasher", "washing machine", "wash clothes", "dry clothes",
                "bake", "baking", "roast", "roasting", "slow cook", "meal prep",
                "defrost", "marinate", "marinating", "charge car", "charge battery"].contains { text.contains(" " + $0 + " ") }
    }

    enum Learned: String { case suggest, auto }

    /// Titles about the same thing: one's words all in the other, or more than half of the longer one's shared.
    static func similar(_ a: String, _ b: String) -> Bool {
        let one = CategorySuggestion.words(a), two = CategorySuggestion.words(b)
        guard !one.isEmpty, !two.isEmpty else { return false }
        let shared = one.intersection(two).count
        return shared == one.count || shared == two.count || shared * 2 > max(one.count, two.count)
    }

    /// Learned start & finish: one similar earlier task that was tracked suggests it, two or more turn it on.
    /// Similar tasks where it was turned off count against. A rule word always turns it on.
    /// Mirrors learnedProgress in windows/ui/planner.js; cases in shared/test-cases/progress-learning.json.
    static func learned(_ title: String, history: [(title: String, tracking: Bool)], ruleWords: [String] = []) -> Learned? {
        let words = CategorySuggestion.words(title)
        if ruleWords.contains(where: { !CategorySuggestion.words($0).isDisjoint(with: words) }) { return .auto }
        var tracked = 0, declined = 0
        for item in history where similar(title, item.title) { if item.tracking { tracked += 1 } else { declined += 1 } }
        guard tracked > declined else { return nil }
        return tracked >= 2 ? .auto : .suggest
    }
}

@MainActor extension TaskProgress {
    /// Tasks where start & finish was chosen either way, read at most once a second so rows stay cheap.
    private static var cache: (at: Date, history: [(id: UUID, title: String, tracking: Bool)])?
    static func learned(for title: String, excluding id: UUID? = nil, in context: ModelContext) -> Learned? {
        if cache == nil || Date.now.timeIntervalSince(cache!.at) > 1 {
            let tasks = (try? context.fetch(FetchDescriptor<PlannerTask>())) ?? []
            cache = (.now, tasks.compactMap { task in
                guard !task.note, let tracking = task.progressTracking else { return nil }
                return (task.id, task.title, tracking)
            })
        }
        let history = cache!.history.filter { $0.id != id }.map { (title: $0.title, tracking: $0.tracking) }
        return learned(title, history: history, ruleWords: CaptureRules.progressWords)
    }
    /// After start & finish is turned on or off, the next read sees it.
    static func forget() { cache = nil }
}
