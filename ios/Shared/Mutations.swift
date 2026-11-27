import Foundation
import SwiftData
import WidgetKit

@MainActor enum Mutations {
    /// Saves and syncs. Deletions and moves can be undone (UndoJournal decides); `undoKind` forces it, as imports do.
    static func save(_ context: ModelContext, undoable: Bool = true, undoKind: UndoJournal.Kind? = nil) throws {
        do {
            // Only the items this edit touched are read and recorded, so a tick costs the same with a
            // year of history as with a day (sync's occasional full check catches anything else).
            let removed = Set(context.deletedModelsArray.compactMap(SyncRecords.key))
            var after: [String: String] = [:]
            for model in context.insertedModelsArray + context.changedModelsArray where !removed.contains(SyncRecords.key(model) ?? "") {
                if let record = try SyncRecords.record(model) { after[record.key] = record.payload }
            }
            for (key, payload) in try SyncRecords.preferenceSnapshots() { after[key] = payload }
            let entries = try SyncRecords.entries(Set(after.keys).union(removed), context: context)
            let before = entries.filter { !$0.value.tombstone }.mapValues(\.payload)
            Breadcrumbs.mark("save: writing")
            SyncRecords.capture(context, records: after, removed: removed, entries: entries); try context.save()
            Breadcrumbs.mark("save: written")
            // Both hold just the touched keys: unchanged ones match and drop out, deleted ones are only in `before`.
            if undoable { UndoJournal.shared.record(before: before, after: after, kind: undoKind) }
            TaskProgress.forget()
            WidgetCenter.shared.reloadAllTimelines()
            Breadcrumbs.mark("save: telling sync")
            NotificationCenter.default.post(name: .init("OrbitLocalChange"), object: nil)
            Breadcrumbs.mark("finished: save")
        }
        catch { context.rollback(); throw error }
    }

    /// Tasks are one-off; only habits repeat.
    static func toggle(_ task: PlannerTask, at date: Date = .now, in context: ModelContext) throws {
        let finishing = task.completedAt == nil, finishedAt = task.completedAt
        if !finishing { task.startedAt = nil }
        task.completedAt = finishing ? date : nil
        task.updatedAt = .now
        // A repeating task makes its next copy when it is ticked off; reopening it takes back an untouched copy.
        if finishing && RepeatRules.valid(task.repeats) && task.nextOccurrenceID == nil {
            try makeNextOccurrence(task, finishedAt: date, in: context)
        } else if !finishing, let nextID = task.nextOccurrenceID {
            let copy = try context.fetch(FetchDescriptor<PlannerTask>(predicate: #Predicate { $0.id == nextID })).first
            var untouched = true
            if let copy {
                untouched = copy.completedAt == nil && (finishedAt.map { abs($0.timeIntervalSince(copy.updatedAt)) < 0.5 } ?? false)
            }
            if untouched {
                if let copy { context.delete(copy) }
                task.nextOccurrenceID = nil
            }
        }
        try save(context)
    }

    /// The next copy of a repeating task (RepeatRules.nextDays): same title, notes, list, length and rule; its
    /// planned day, time, due date and reminders move forward; steps start unticked. Its `updatedAt` is the
    /// moment the original was finished, so reopening the original can tell the copy hasn't been touched.
    static func makeNextOccurrence(_ task: PlannerTask, finishedAt date: Date, in context: ModelContext) throws {
        guard let days = RepeatRules.nextDays(day: task.day, deadline: task.deadline, rule: task.repeats,
                                              every: task.repeatEvery ?? 1, completedDay: PlannerLogic.plannerDay(date)),
              let anchor = days.day ?? days.deadline else { return }
        let id = RepeatRules.occurrenceID(task.id, day: anchor)
        task.nextOccurrenceID = id
        // Another device may have made it already (same ID).
        guard try context.fetch(FetchDescriptor<PlannerTask>(predicate: #Predicate { $0.id == id })).isEmpty else { return }
        let copy = PlannerTask(title: task.title, listID: task.listID)
        copy.id = id
        copy.notes = task.notes; copy.durationMinutes = task.durationMinutes; copy.priority = task.priority
        copy.tags = task.tags; copy.subtasks = task.subtasks.map { Subtask(id: $0.id, title: $0.title, completed: false) }
        copy.repeats = task.repeats; copy.repeatEvery = task.repeatEvery ?? 1
        copy.deadline = days.deadline
        if task.progressTracking == true { copy.progressTracking = true }
        // Times keep their clock time on the new day; reminders keep their distance from it.
        var shift = 0
        if let newDay = days.day {
            if let oldDay = task.day, let from = HabitRules.date(oldDay), let to = HabitRules.date(newDay) {
                shift = Int((to.timeIntervalSince(from) / 86_400).rounded())
            }
            if task.hasTime, let start = task.dueDate, task.day != nil,
               let moved = Calendar.current.date(byAdding: .day, value: shift, to: start) {
                copy.schedule(moved, hasTime: true)
            } else {
                copy.schedule(day: newDay)
            }
        }
        copy.reminders = task.day == nil || days.day == nil ? [] : task.reminders.compactMap { Calendar.current.date(byAdding: .day, value: shift, to: $0) }
        copy.sortOrder = task.sortOrder
        copy.updatedAt = date
        context.insert(copy)
    }

    static func setProgress(_ task: PlannerTask, enabled: Bool, start: Bool = false, in context: ModelContext) throws {
        task.progressTracking = enabled
        task.startedAt = enabled && start ? .now : nil
        task.updatedAt = .now
        try save(context)
    }

    /// An avoid habit: marks the day as a slip (count HabitRules.slip), or takes the slip back (count 0).
    /// A slipped day can't be ticked and ends the streak.
    static func slip(_ habit: Habit, at date: Date, slipped: Bool = true, in context: ModelContext) throws {
        let id = habit.id, key = PlannerLogic.dayKey(date)
        let logs = try context.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id }))
        let count = slipped ? HabitRules.slip : 0
        if let log = logs.first(where: { $0.dayKey == key }) { log.count = count; log.updatedAt = .now }
        else if slipped { context.insert(HabitLog(habitID: id, dayKey: key, count: count)) }
        try save(context)
    }

    static func log(_ habit: Habit, at date: Date, in context: ModelContext) throws {
        let id = habit.id, key = PlannerLogic.dayKey(date)
        let logs = try context.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id }))
        if PlannerLogic.checkedToday(habit, logs: logs, at: date) { return }
        if let log = logs.first(where: { $0.dayKey == key }) {
            if log.count < 0 { return } // a slipped day stays failed until the slip is taken back
            log.count += 1; log.updatedAt = .now
        } else { context.insert(HabitLog(habitID: id, dayKey: key)) }
        try save(context)
    }

    static func undoLog(_ habit: Habit, at date: Date, in context: ModelContext) throws {
        let id = habit.id, key = PlannerLogic.dayKey(date)
        let logs = try context.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id && $0.dayKey == key }))
        if let log = logs.first, log.count > 0 { log.count -= 1; log.updatedAt = .now }
        try save(context)
    }

    /// Marks yesterday complete in one action. Callers intentionally expose no older backfill.
    static func backfillYesterday(_ habit: Habit, now: Date = .now, in context: ModelContext) throws {
        let calendar = Calendar.current
        guard let yesterday = calendar.date(byAdding: .day, value: -1, to: now) else { return }
        let id = habit.id, key = PlannerLogic.dayKey(yesterday)
        let target = PlannerLogic.dailyTarget(habit)
        let logs = try context.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id }))
        if let log = logs.first(where: { $0.dayKey == key }) { log.count = max(log.count, target); log.updatedAt = .now }
        else { context.insert(HabitLog(habitID: id, dayKey: key, count: target)) }
        try save(context)
    }
}
