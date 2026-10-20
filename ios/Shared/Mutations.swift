import Foundation
import SwiftData
import WidgetKit

@MainActor enum Mutations {
    static func save(_ context: ModelContext, undoable: Bool = true) throws {
        do {
            let before = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SyncEntry>()).filter { $0.key != "owner" && !$0.tombstone }.map { ($0.key, $0.payload) })
            let after = try SyncRecords.snapshots(context)
            try SyncRecords.capture(context, snapshots: after); try context.save()
            if undoable { UndoJournal.shared.record(before: before, after: after) }
            WidgetCenter.shared.reloadAllTimelines(); NotificationCenter.default.post(name: .init("OrbitLocalChange"), object: nil)
        }
        catch { context.rollback(); throw error }
    }

    static func toggle(_ task: PlannerTask, in context: ModelContext) throws {
        if task.completedAt != nil {
            task.completedAt = nil
        } else {
            task.completedAt = .now
            if task.nextOccurrenceID == nil, let date = task.dueDate,
               let next = PlannerLogic.nextOccurrence(after: date, rule: task.recurrenceRule) {
                let successor = PlannerTask(title: task.title, dueDate: next, hasTime: task.hasTime, listID: task.listID)
                successor.notes = task.notes; successor.priority = task.priority; successor.tags = task.tags
                successor.durationMinutes = task.durationMinutes; successor.recurrenceRule = task.recurrenceRule
                successor.subtasks = task.subtasks.map { Subtask(title: $0.title) }
                successor.reminders = task.reminders.map { next.addingTimeInterval($0.timeIntervalSince(date)) }
                task.nextOccurrenceID = successor.id
                context.insert(successor)
            }
        }
        task.updatedAt = .now
        try save(context)
    }

    static func log(_ habit: Habit, at date: Date, in context: ModelContext) throws {
        let id = habit.id, key = PlannerLogic.dayKey(date)
        let logs = try context.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id }))
        if PlannerLogic.checkedToday(habit, logs: logs, at: date) { return }
        if let log = logs.first(where: { $0.dayKey == key }) { log.count += 1; log.updatedAt = .now }
        else { context.insert(HabitLog(habitID: id, dayKey: key)) }
        try save(context)
    }

    static func undoLog(_ habit: Habit, at date: Date, in context: ModelContext) throws {
        let id = habit.id, key = PlannerLogic.dayKey(date)
        let logs = try context.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id && $0.dayKey == key }))
        if let log = logs.first { log.count = max(0, log.count - 1); log.updatedAt = .now }
        try save(context)
    }
}
