import Foundation
import SwiftData

/// Data migrations that run on launch and after each sync, so records from older devices are updated too.
@MainActor enum Migrations {
    /// Open repeating tasks become habits with the same ID; earlier completed occurrences become
    /// check-ins (their task records stay). Monthly and custom rules become one-off tasks on their date.
    /// The result depends only on the records, matching windows/ui/conversions.js `migrateRecurring`,
    /// so two devices migrating the same data agree. Records awaiting conflict review are skipped.
    @discardableResult static func run(_ context: ModelContext) throws -> Int {
        let anchored = try anchorAllDayTasks(context)
        let conflicted = Set(try context.fetch(FetchDescriptor<SyncEntry>()).filter { $0.conflict != nil }.map(\.key))
        let tasks = try context.fetch(FetchDescriptor<PlannerTask>())
        let previous = Dictionary(tasks.compactMap { task in task.nextOccurrenceID.map { ($0, task) } }, uniquingKeysWith: { first, _ in first })
        let existing = Set(try context.fetch(FetchDescriptor<HabitLog>()).map { $0.habitID.uuidString + $0.dayKey })
        var changed = 0
        for task in tasks where !task.recurrenceRule.isEmpty && task.nextOccurrenceID == nil && task.completedAt == nil
            && !conflicted.contains("tasks/" + task.id.uuidString.lowercased()) {
            changed += 1
            guard Conversions.scheduleForRule[task.recurrenceRule] != nil else {
                task.recurrenceRule = ""; task.updatedAt = .now; continue
            }
            var checkIns: [(id: UUID, day: String)] = []
            var cursor = previous[task.id], guardCount = 0
            while let earlier = cursor, guardCount < 10_000 {
                if let done = earlier.completedAt {
                    let day = PlannerLogic.dayKey(done)
                    if !checkIns.contains(where: { $0.day == day }) && !existing.contains(task.id.uuidString + day) { checkIns.append((earlier.id, day)) }
                }
                cursor = previous[earlier.id]; guardCount += 1
            }
            let firstDay = (checkIns.map(\.day) + [task.dueDate.map { PlannerLogic.dayKey($0) }].compactMap { $0 }).min()
            let createdAt = firstDay.flatMap(localStart) ?? .now
            let id = task.id
            try Conversions.toHabit(task, in: context, createdAt: createdAt, save: false)
            // A habit restored from a backup may already have some of these days.
            let present = Set(try context.fetch(FetchDescriptor<HabitLog>(predicate: #Predicate { $0.habitID == id })).map(\.dayKey))
            for checkIn in checkIns where !present.contains(checkIn.day) {
                let log = HabitLog(habitID: id, dayKey: checkIn.day); log.id = checkIn.id; context.insert(log)
            }
        }
        if changed > 0 || anchored { try Mutations.save(context, undoable: false) }
        return changed
    }

    /// All-day tasks are floating calendar days. Fills `localDate` for records saved by older versions
    /// and moves the cached midnight into the current time zone (after travel). The synced payload
    /// is unchanged, so nothing is re-uploaded.
    static func anchorAllDayTasks(_ context: ModelContext, calendar: Calendar = .current) throws -> Bool {
        var changed = false
        for task in try context.fetch(FetchDescriptor<PlannerTask>()) where !task.hasTime && task.dueDate != nil {
            let day = task.localDate ?? PlannerLogic.dayKey(task.dueDate!, calendar: calendar)
            let start = QuickAdd.start(of: day, time: nil, calendar: calendar)
            if task.localDate != day || task.dueDate != start { task.localDate = day; task.dueDate = start; changed = true }
        }
        return changed
    }
    private static func localStart(_ key: String) -> Date? {
        let formatter = DateFormatter(); formatter.locale = Locale(identifier: "en_US_POSIX"); formatter.dateFormat = "yyyy-MM-dd"
        return formatter.date(from: key).map { Calendar.current.startOfDay(for: $0) }
    }
}
