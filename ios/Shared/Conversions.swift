import Foundation
import SwiftData

/// Keep the source's extra fields so moving back does not discard notes or history.
@MainActor enum Conversions {
    static func remove(_ habit: Habit, in context: ModelContext) throws {
        let id = habit.id
        for log in try context.fetch(FetchDescriptor<HabitLog>()).filter({ $0.habitID == id }) { context.delete(log) }
        context.delete(habit)
        try Mutations.save(context)
    }

    static func toHabit(_ task: PlannerTask, in context: ModelContext) throws {
        let key = "tasks/" + task.id.uuidString.lowercased()
        var payload = try SyncRecords.object(try SyncRecords.snapshots(context)[key]!)
        payload.removeValue(forKey: "conversionData")
        let habit: Habit
        if let backup = task.conversionData, let source = try SyncRecords.object(backup)["source"] as? [String: Any] {
            try SyncRecords.apply(["key": "habits/" + task.id.uuidString.lowercased(), "payload": source], context: context)
            habit = try context.fetch(FetchDescriptor<Habit>()).first { $0.id == task.id }!
            if let logs = try SyncRecords.object(backup)["logs"] as? [[String: Any]] {
                for log in logs { try SyncRecords.apply(["key": "habit_logs/restored", "payload": log], context: context) }
            }
        } else {
            habit = Habit(title: task.title, frequencyRule: task.recurrenceRule == "FREQ=WEEKLY" ? "WEEKLY" : "DAILY")
            habit.id = task.id; context.insert(habit)
            if let reminder = task.reminders.first {
                habit.reminderMinutes = Calendar.current.component(.hour, from: reminder) * 60 + Calendar.current.component(.minute, from: reminder)
            }
            if let done = task.completedAt, Calendar.current.isDateInToday(done) {
                context.insert(HabitLog(habitID: habit.id, dayKey: PlannerLogic.dayKey(done)))
            }
        }
        habit.title = task.title; habit.updatedAt = .now
        habit.conversionData = try SyncRecords.json(["source": payload])
        context.delete(task)
        try Mutations.save(context)
    }

    static func toTask(_ habit: Habit, in context: ModelContext) throws {
        let snapshots = try SyncRecords.snapshots(context)
        var payload = try SyncRecords.object(snapshots["habits/" + habit.id.uuidString.lowercased()]!)
        payload.removeValue(forKey: "conversionData")
        let logs = try context.fetch(FetchDescriptor<HabitLog>()).filter { $0.habitID == habit.id }
        let history = try snapshots.filter { $0.key.hasPrefix("habit_logs/" + habit.id.uuidString.lowercased() + "-") }.map { try SyncRecords.object($0.value) }
        let task: PlannerTask
        if let backup = habit.conversionData, let source = try SyncRecords.object(backup)["source"] as? [String: Any] {
            try SyncRecords.apply(["key": "tasks/" + habit.id.uuidString.lowercased(), "payload": source], context: context)
            task = try context.fetch(FetchDescriptor<PlannerTask>()).first { $0.id == habit.id }!
        } else {
            task = PlannerTask(title: habit.title, dueDate: Calendar.current.startOfDay(for: .now))
            task.id = habit.id; context.insert(task)
        }
        task.title = habit.title; task.updatedAt = .now
        task.completedAt = PlannerLogic.progress(habit, logs: logs, at: .now) >= habit.target ? .now : nil
        task.conversionData = try SyncRecords.json(["source": payload, "logs": history])
        for log in logs { context.delete(log) }
        context.delete(habit)
        try Mutations.save(context)
    }
}
