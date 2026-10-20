import Foundation
import SwiftData

/// Saves a quick add result. Used by quick capture, the Add to Orbit intent and the share extension,
/// so text becomes the same task or habit wherever it is entered.
@MainActor enum QuickAddSaver {
    /// - Parameters:
    ///   - listID: the list being viewed, if any; a #list in the text or "someday" wins.
    ///   - notes: extra text for a task, such as a shared web address.
    @discardableResult
    static func save(_ result: QuickAddResult, listID: UUID? = nil, notes: String = "", in context: ModelContext) throws -> String {
        guard !result.title.isEmpty else { throw CocoaError(.validationMissingMandatoryProperty) }
        if result.kind == .habit {
            // Anything that repeats is a habit; a time becomes its reminder.
            let habit = Habit(title: result.title, frequencyRule: result.schedule ?? "DAILY")
            habit.reminderMinutes = result.time
            context.insert(habit)
        } else {
            let start = result.date.flatMap { QuickAdd.start(of: $0, time: result.time) }
            let task = PlannerTask(title: result.title, dueDate: start, hasTime: start != nil && result.time != nil, listID: try list(for: result, viewing: listID, in: context))
            task.notes = notes
            context.insert(task)
            if task.listID == TodayRules.somedayID { try TodayRules.moveToSomeday(task, in: context) }
        }
        try Mutations.save(context)
        return QuickAdd.describe(result)
    }

    /// Someday wins; then a #list (created when new); then the list being viewed. A dated item can't stay in Someday.
    static func list(for result: QuickAddResult, viewing listID: UUID?, in context: ModelContext) throws -> UUID? {
        if result.someday { try TodayRules.ensureSomeday(context); return TodayRules.somedayID }
        if let name = result.list {
            let lists = try context.fetch(FetchDescriptor<TaskList>(sortBy: [SortDescriptor(\.sortOrder)]))
            if let existing = lists.first(where: { $0.id != TodayRules.somedayID && $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }) { return existing.id }
            let list = TaskList(name: name, sortOrder: lists.count); context.insert(list); return list.id
        }
        if listID == TodayRules.somedayID && result.date != nil { return nil }
        if listID == TodayRules.somedayID { try TodayRules.ensureSomeday(context) }
        return listID
    }
}
