import AppIntents
import Foundation
import SwiftData

/// A task or habit, as Shortcuts and Siri see it. IDs are "task:<uuid>" or "habit:<uuid>".
struct OrbitItem: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Item"
    static var defaultQuery = OrbitItemQuery()
    var id: String
    var title: String
    var displayRepresentation: DisplayRepresentation { DisplayRepresentation(title: "\(title)") }
}

struct OrbitItemQuery: EntityQuery {
    @MainActor func entities(for identifiers: [String]) async throws -> [OrbitItem] {
        let context = ModelContext(try Persistence.makeContainer())
        let tasks = try context.fetch(FetchDescriptor<PlannerTask>()), habits = try context.fetch(FetchDescriptor<Habit>())
        return identifiers.compactMap { id in
            if let task = tasks.first(where: { "task:" + $0.id.uuidString == id }) { return OrbitItem(id: id, title: task.title) }
            if let habit = habits.first(where: { "habit:" + $0.id.uuidString == id }) { return OrbitItem(id: id, title: habit.title) }
            return nil
        }
    }
    /// Today's open tasks and the habits still due today.
    @MainActor func suggestedEntities() async throws -> [OrbitItem] {
        let context = ModelContext(try Persistence.makeContainer())
        let today = PlannerLogic.dayKey(.now)
        let logs = try context.fetch(FetchDescriptor<HabitLog>())
        let tasks = try context.fetch(FetchDescriptor<PlannerTask>(sortBy: [SortDescriptor(\.sortOrder)]))
            .filter { $0.completedAt == nil && TodayRules.onDay(TodayRules.item($0), day: today, today: today) }
        let habits = try context.fetch(FetchDescriptor<Habit>(sortBy: [SortDescriptor(\.createdAt)]))
            .filter { PlannerLogic.isDue($0, logs: logs, at: .now) && !PlannerLogic.checkedToday($0, logs: logs, at: .now) }
        return tasks.map { OrbitItem(id: "task:" + $0.id.uuidString, title: $0.title) } + habits.map { OrbitItem(id: "habit:" + $0.id.uuidString, title: $0.title) }
    }
}

/// Completes a task or checks a habit for today. The widget's ticks and Shortcuts/Siri both use it.
struct CompleteItemIntent: AppIntent {
    static var title: LocalizedStringResource = "Complete Item"
    static var description = IntentDescription("Tick off one of today’s tasks or habits.")
    static var openAppWhenRun = false
    @Parameter(title: "Item") var item: OrbitItem
    init() {}
    init(itemID: String, isHabit: Bool) { item = OrbitItem(id: (isHabit ? "habit:" : "task:") + itemID, title: "") }
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let parts = item.id.split(separator: ":", maxSplits: 1).map(String.init)
        guard parts.count == 2, let id = UUID(uuidString: parts[1]) else { return .result(dialog: "That item is no longer in Orbit.") }
        let context = ModelContext(try Persistence.makeContainer())
        context.autosaveEnabled = false
        var title = item.title
        if parts[0] == "habit", let habit = try context.fetch(FetchDescriptor<Habit>(predicate: #Predicate { $0.id == id })).first {
            try Mutations.log(habit, at: .now, in: context); title = habit.title
        } else if let task = try context.fetch(FetchDescriptor<PlannerTask>(predicate: #Predicate { $0.id == id })).first {
            if task.completedAt == nil { try Mutations.toggle(task, in: context) }
            title = task.title
        } else { return .result(dialog: "That item is no longer in Orbit.") }
        try await NotificationScheduler.shared.replace(with: NotificationScheduler.reminders(context: context))
        return .result(dialog: "Done: \(title)")
    }
}

/// Adds text with quick add rules: "gym tomorrow 6pm", "read every day", "someday".
struct AddToOrbitIntent: AppIntent {
    static var title: LocalizedStringResource = "Add to Orbit"
    static var description = IntentDescription("Add a task or habit. Include a day or time, such as “tomorrow at 6pm”, or say “every day” for a habit.")
    static var openAppWhenRun = false
    @Parameter(title: "Text", requestValueDialog: "What would you like to add?") var text: String
    static var parameterSummary: some ParameterSummary { Summary("Add \(\.$text) to Orbit") }
    init() {}
    @MainActor func perform() async throws -> some IntentResult & ProvidesDialog {
        let result = QuickAdd.parse(text)
        guard !result.title.isEmpty else { return .result(dialog: "Add a title as well as a time.") }
        let context = ModelContext(try Persistence.makeContainer())
        context.autosaveEnabled = false
        let summary = try QuickAddSaver.save(result, in: context)
        try await NotificationScheduler.shared.replace(with: NotificationScheduler.reminders(context: context))
        return .result(dialog: "Added “\(result.title)” · \(summary)")
    }
}
