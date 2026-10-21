import Foundation
import SwiftData
import WidgetKit

@MainActor enum Mutations {
    /// Saves and syncs. Deletions and moves can be undone (UndoJournal decides); `undoKind` forces it, as imports do.
    static func save(_ context: ModelContext, undoable: Bool = true, undoKind: UndoJournal.Kind? = nil) throws {
        do {
            let before = Dictionary(uniqueKeysWithValues: try context.fetch(FetchDescriptor<SyncEntry>()).filter { $0.key != "owner" && !$0.tombstone }.map { ($0.key, $0.payload) })
            let after = try SyncRecords.snapshots(context)
            try SyncRecords.capture(context, snapshots: after); try context.save()
            if undoable { UndoJournal.shared.record(before: before, after: after, kind: undoKind) }
            WidgetCenter.shared.reloadAllTimelines(); NotificationCenter.default.post(name: .init("OrbitLocalChange"), object: nil)
        }
        catch { context.rollback(); throw error }
    }

    /// Tasks are one-off; only habits repeat.
    static func toggle(_ task: PlannerTask, in context: ModelContext) throws {
        task.completedAt = task.completedAt == nil ? .now : nil
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
