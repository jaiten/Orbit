import Foundation
import SwiftData

/// What belongs on Today, and the moves between Today, Later and Someday.
/// Mirrors windows/ui/planner.js; cases in shared/test-cases/today.json.
enum TodayRules {
    /// The built-in Someday list has the same ID on every device, so creating it twice never conflicts.
    static let somedayID = UUID(uuidString: "00000000-0000-4000-8000-000000000001")!

    struct Item { var day: String?; var completedDay: String?; var someday: Bool }

    /// Today shows items dated today or earlier that are still open, plus anything finished today.
    /// Another day shows only items dated that day. Undated and Someday items never appear.
    static func onDay(_ item: Item, day: String, today: String) -> Bool {
        guard !item.someday, let date = item.day else { return false }
        if day == today ? date > day : date != day { return false }
        return item.completedDay == nil || item.completedDay == day
    }
    static func isOverdue(_ item: Item, today: String) -> Bool {
        !item.someday && item.completedDay == nil && (item.day.map { $0 < today } ?? false)
    }
    static func item(_ task: PlannerTask) -> Item {
        Item(day: task.day, completedDay: task.completedAt.map { PlannerLogic.dayKey($0) }, someday: task.listID == somedayID)
    }
    /// "from Tue" within the last week, otherwise "from Oct 12".
    static func overdueLabel(_ day: String, today: String) -> String {
        guard let date = HabitRules.date(day), let now = HabitRules.date(today) else { return "" }
        var utc = Calendar(identifier: .gregorian); utc.timeZone = TimeZone(identifier: "UTC")!
        let recent = utc.dateComponents([.day], from: date, to: now).day ?? 99 < 7
        var style: Date.FormatStyle = recent ? .dateTime.weekday(.abbreviated) : .dateTime.month(.abbreviated).day()
        style.timeZone = utc.timeZone
        return "from " + date.formatted(style)
    }
}

@MainActor extension TodayRules {
    static func ensureSomeday(_ context: ModelContext) throws {
        let id = somedayID
        guard try context.fetch(FetchDescriptor<TaskList>(predicate: #Predicate { $0.id == id })).isEmpty else { return }
        let list = TaskList(name: "Someday", color: "lavender", sortOrder: -1); list.id = id
        context.insert(list)
    }
    /// Moves a task to `day`, keeping its time of day and reminder offsets. Someday items leave Someday.
    static func moveToDay(_ task: PlannerTask, day: Date, calendar: Calendar = .current) {
        let start = calendar.startOfDay(for: day)
        if task.hasTime, let old = task.dueDate {
            let clock = calendar.dateComponents([.hour, .minute], from: old)
            let next = calendar.date(bySettingHour: clock.hour ?? 0, minute: clock.minute ?? 0, second: 0, of: start)!
            task.reminders = task.reminders.map { next.addingTimeInterval($0.timeIntervalSince(old)) }
            task.schedule(next, hasTime: true)
        } else { task.schedule(start, hasTime: false, calendar: calendar) }
        if task.listID == somedayID { task.listID = nil }
        task.updatedAt = .now
    }
    /// Later: no date, so it waits in its list until it is added to Today again.
    static func moveLater(_ task: PlannerTask) {
        task.schedule(nil, hasTime: false); task.reminders = []; task.updatedAt = .now
    }
    /// Someday: no date, no reminders, never on Today.
    static func moveToSomeday(_ task: PlannerTask, in context: ModelContext) throws {
        try ensureSomeday(context); moveLater(task); task.listID = somedayID
    }
}
