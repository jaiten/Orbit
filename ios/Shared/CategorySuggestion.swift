import Foundation
import SwiftData

/// Suggests a category for a new task from earlier tasks with similar titles.
/// Mirrors suggestCategory in windows/ui/planner.js; cases in shared/test-cases/category-suggestions.json.
enum CategorySuggestion {
    private static let stopWords: Set<String> = Set("the and for with from into about this that your our get make some more then than have need new week".split(separator: " ").map(String.init))

    /// Words of three or more letters, minus common words, with a trailing "s" dropped.
    static func words(_ title: String) -> Set<String> {
        Set(title.lowercased().split { !$0.isLetter && !$0.isNumber }.map(String.init)
            .filter { $0.count >= 3 && !stopWords.contains($0) }
            .map { $0.count > 3 && $0.hasSuffix("s") ? String($0.dropLast()) : $0 })
    }

    /// Each category scores the words its tasks share with `title`; the top score wins unless it ties.
    static func suggest<Category: Hashable>(_ title: String, history: [(title: String, category: Category)]) -> Category? {
        let wanted = words(title)
        guard !wanted.isEmpty else { return nil }
        var scores: [Category: Int] = [:]
        for item in history {
            let shared = words(item.title).intersection(wanted).count
            if shared > 0 { scores[item.category, default: 0] += shared }
        }
        let ranked = scores.sorted { $0.value > $1.value }
        guard let best = ranked.first, ranked.count == 1 || best.value > ranked[1].value else { return nil }
        return best.key
    }
}

@MainActor extension CategorySuggestion {
    /// The suggested category for a quick add, or nil when the text already chooses a list or Someday.
    static func suggest(for result: QuickAddResult, in context: ModelContext) -> TaskList? {
        guard result.kind == .task, !result.someday, result.list == nil, !result.title.isEmpty,
              let lists = try? context.fetch(FetchDescriptor<TaskList>()) else { return nil }
        let categories = lists.filter(\.isUserCategory)
        guard !categories.isEmpty, let tasks = try? context.fetch(FetchDescriptor<PlannerTask>()) else { return nil }
        let ids = Set(categories.map(\.id))
        let history = tasks.compactMap { task -> (title: String, category: UUID)? in
            guard !task.note, let id = task.listID, ids.contains(id) else { return nil }
            return (task.title, id)
        }
        guard let id = suggest(result.title, history: history) else { return nil }
        return categories.first { $0.id == id }
    }
}
