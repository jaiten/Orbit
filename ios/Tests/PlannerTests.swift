import XCTest
import SwiftData
@testable import DayOS

@MainActor final class PlannerTests: XCTestCase {
    private var calendar: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Vancouver")!
        c.firstWeekday = 2
        return c
    }
    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int = 12) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }
    func testQuickAddTomorrowAndTime() {
        let result = QuickAdd.parse("gym tomorrow 6am", now: date(2026, 9, 14), calendar: calendar)
        XCTAssertEqual(result.title, "gym"); XCTAssertTrue(result.hasTime)
        XCTAssertEqual(result.date, date(2026, 9, 15, 6))
    }
    func testBarePastTimeMovesToTomorrow() {
        let result = QuickAdd.parse("Read 6am", now: date(2026, 9, 14), calendar: calendar)
        XCTAssertEqual(result.date, date(2026, 9, 15, 6))
        XCTAssertEqual(QuickAdd.parse("Buy 13 apples", now: date(2026, 9, 14), calendar: calendar).title, "Buy 13 apples")
    }
    func testRecurrenceKeepsWallClockAcrossDST() {
        let result = PlannerLogic.nextOccurrence(after: date(2026, 3, 7, 8), rule: "FREQ=DAILY", calendar: calendar)
        XCTAssertEqual(result, date(2026, 3, 8, 8))
        XCTAssertNil(PlannerLogic.nextOccurrence(after: .now, rule: "FREQ=HOURLY"))
    }
    func testStreakAllowsUnfinishedTodayAndBreaksOnGap() {
        let habit = Habit(title: "Read"); habit.createdAt = date(2026, 9, 1)
        let logs = [13, 12, 10].map { HabitLog(habitID: habit.id, dayKey: PlannerLogic.dayKey(date(2026, 9, $0), calendar: calendar)) }
        XCTAssertEqual(PlannerLogic.streak(habit, logs: logs, at: date(2026, 9, 14), calendar: calendar), 2)
    }
    func testWeeklyTargetUsesCalendarBoundaries() {
        let habit = Habit(title: "Move", frequencyRule: "WEEKLY", target: 3)
        let logs = [13, 14, 15].map { HabitLog(habitID: habit.id, dayKey: PlannerLogic.dayKey(date(2026, 9, $0), calendar: calendar)) }
        XCTAssertEqual(PlannerLogic.progress(habit, logs: logs, at: date(2026, 9, 15), calendar: calendar), 2)
    }
    func testWeeklyStreakIncludesPartialCreationWeek() {
        let habit = Habit(title: "Move", frequencyRule: "WEEKLY", target: 1)
        habit.createdAt = date(2026, 9, 10)
        let logs = [HabitLog(habitID: habit.id, dayKey: "2026-09-11")]
        XCTAssertEqual(PlannerLogic.streak(habit, logs: logs, at: date(2026, 9, 14), calendar: calendar), 1)
    }
    func testRecurringCompletionDoesNotDuplicateOnReopen() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let task = PlannerTask(title: "Read", dueDate: .now); task.recurrenceRule = "FREQ=DAILY"
        context.insert(task); try Mutations.save(context)
        try Mutations.toggle(task, in: context)
        try Mutations.toggle(task, in: context)
        try Mutations.toggle(task, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannerTask>()), 2)
    }
    func testHabitLogTargetAndUndo() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let habit = Habit(title: "Water", target: 2); context.insert(habit)
        try Mutations.log(habit, at: .now, in: context)
        try Mutations.log(habit, at: .now, in: context)
        try Mutations.log(habit, at: .now, in: context)
        var logs = try context.fetch(FetchDescriptor<HabitLog>())
        XCTAssertEqual(logs.count, 1); XCTAssertEqual(logs.first?.count, 2)
        try Mutations.undoLog(habit, at: .now, in: context)
        logs = try context.fetch(FetchDescriptor<HabitLog>())
        XCTAssertEqual(logs.first?.count, 1)
    }
    func testDiskRoundTrip() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("test.store")
        func open() throws -> ModelContainer {
            try ModelContainer(for: Persistence.schema, configurations: [ModelConfiguration(schema: Persistence.schema, url: url, cloudKitDatabase: .none)])
        }
        do {
            let container = try open(); let context = ModelContext(container)
            let task = PlannerTask(title: "Persistent intention")
            task.subtasks = [Subtask(title: "First step")]; task.tags = ["personal"]; task.reminders = [.now]
            context.insert(task); try context.save()
        }
        let container = try open(); let context = ModelContext(container)
        let loaded = try XCTUnwrap(context.fetch(FetchDescriptor<PlannerTask>()).first)
        XCTAssertEqual(loaded.title, "Persistent intention"); XCTAssertEqual(loaded.subtasks.first?.title, "First step")
        XCTAssertEqual(loaded.tags, ["personal"]); XCTAssertEqual(loaded.reminders.count, 1)
    }
}
