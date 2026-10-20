import XCTest
import SwiftData
@testable import Orbit

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
    func testLocalTimeSuggestionRequiresDistinctDays() {
        let name = "OrbitUsageTests." + UUID().uuidString
        let defaults = UserDefaults(suiteName: name)!
        defer { defaults.removePersistentDomain(forName: name) }
        let first = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 14, hour: 10))!
        UsageSignals.recordVisit(now: first, defaults: defaults)
        UsageSignals.recordVisit(now: first.addingTimeInterval(60), defaults: defaults)
        XCTAssertEqual(defaults.integer(forKey: "orbitVisitDays"), 1)
        XCTAssertEqual(UsageSignals.suggestedMinutes(defaults: defaults), 1080)
        for offset in 1...2 { UsageSignals.recordVisit(now: Calendar.current.date(byAdding: .day, value: offset, to: first)!, defaults: defaults) }
        XCTAssertEqual(defaults.integer(forKey: "orbitVisitDays"), 3)
        XCTAssertEqual(UsageSignals.suggestedMinutes(defaults: defaults), 600)
    }
    func testPartialDailyConsistencyAndCreationBoundary() {
        let earlier = date(2026, 9, 13)
        let water = Habit(title: "Water", target: 4); water.createdAt = earlier
        let read = Habit(title: "Read"); read.createdAt = earlier
        let future = Habit(title: "Future"); future.createdAt = date(2026, 9, 16)
        let logs = [HabitLog(habitID: water.id, dayKey: "2026-09-14", count: 2), HabitLog(habitID: read.id, dayKey: "2026-09-14")]
        XCTAssertEqual(PlannerLogic.dailyConsistency(habits: [water, read, future], logs: logs, on: date(2026, 9, 14), calendar: calendar), 0.75, accuracy: 0.001)
        XCTAssertEqual(PlannerLogic.dailyConsistency(habits: [], logs: logs, on: earlier), 0)
    }
    func testWeekdayAndWeekendRecurrence() {
        XCTAssertEqual(PlannerLogic.nextOccurrence(after: date(2026, 9, 18, 8), rule: "FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR", calendar: calendar), date(2026, 9, 21, 8))
        XCTAssertEqual(PlannerLogic.nextOccurrence(after: date(2026, 9, 20, 8), rule: "FREQ=WEEKLY;BYDAY=SA,SU", calendar: calendar), date(2026, 9, 26, 8))
    }
    func testQuickAddTomorrowAndTime() {
        let result = QuickAdd.parse("gym tomorrow 6am", now: date(2026, 9, 14), calendar: calendar)
        XCTAssertEqual(result.title, "gym"); XCTAssertTrue(result.hasTime)
        XCTAssertEqual(result.date, date(2026, 9, 15, 6))
    }
    func testQuickCaptureKeepsChosenCalendarDay() {
        let result = QuickAdd.parse("Read 6am", now: date(2026, 9, 14), calendar: calendar, plannedDay: date(2026, 9, 20))
        XCTAssertEqual(result.date, date(2026, 9, 20, 6))
        let explicit = QuickAdd.parse("Read tomorrow 6am", now: date(2026, 9, 14), calendar: calendar, plannedDay: date(2026, 9, 20))
        XCTAssertEqual(explicit.date, date(2026, 9, 15, 6))
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
    func testTaskConversionPreservesDetailsAndDeletionOutbox() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let task = PlannerTask(title: "Read")
        task.notes = "Chapter two"; task.tags = ["personal"]
        task.subtasks = [Subtask(title: "Choose a book")]
        let id = task.id
        context.insert(task); try Mutations.save(context)
        try Conversions.toHabit(task, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<PlannerTask>()), 0)
        let habit = try XCTUnwrap(context.fetch(FetchDescriptor<Habit>()).first)
        try Conversions.toTask(habit, in: context)
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<PlannerTask>()).first)
        XCTAssertEqual(restored.id, id)
        XCTAssertEqual(restored.notes, "Chapter two")
        XCTAssertEqual(restored.tags, ["personal"])
        XCTAssertEqual(restored.subtasks.first?.title, "Choose a book")
        let entries = try context.fetch(FetchDescriptor<SyncEntry>())
        XCTAssertTrue(try XCTUnwrap(entries.first { $0.key == "habits/" + id.uuidString.lowercased() }).tombstone)
    }
    func testHabitConversionRestoresHistory() throws {
        let container = try Persistence.makeContainer(inMemory: true)
        let context = ModelContext(container)
        let habit = Habit(title: "Water", target: 4)
        context.insert(habit)
        context.insert(HabitLog(habitID: habit.id, dayKey: "2026-09-01"))
        try Mutations.save(context)
        try Conversions.toTask(habit, in: context)
        XCTAssertEqual(try context.fetchCount(FetchDescriptor<HabitLog>()), 0)
        let task = try XCTUnwrap(context.fetch(FetchDescriptor<PlannerTask>()).first)
        try Conversions.toHabit(task, in: context)
        let restored = try XCTUnwrap(context.fetch(FetchDescriptor<Habit>()).first)
        XCTAssertEqual(restored.target, 4)
        XCTAssertEqual(try context.fetch(FetchDescriptor<HabitLog>()).first?.dayKey, "2026-09-01")
    }
    func testEmailCallbackDoesNotImportOrExposeTokens() {
        XCTAssertNil(AuthConfirmation.notice(for: URL(string: "orbit://auth.evil/")!))
        XCTAssertNil(AuthConfirmation.notice(for: URL(string: "https://auth/")!))
        let notice = AuthConfirmation.notice(for: URL(string: "orbit://auth#access_token=private")!)
        XCTAssertTrue(notice?.contains("Sign in") == true)
        XCTAssertFalse(notice?.contains("private") == true)
        XCTAssertTrue(AuthConfirmation.notice(for: URL(string: "orbit://auth#error_code=otp_expired")!)?.contains("fresh email") == true)
    }
    func testSyncIgnoresMetadataAndMergesDifferentFields() throws {
        let base: [String: Any] = ["id": "a", "title": "Read", "notes": "First", "updatedAt": 1]
        var local = base; local["title"] = "Read more"; local["updatedAt"] = 3
        var remote = base; remote["notes"] = "Second"; remote["updatedAt"] = 2
        let merged = try XCTUnwrap(SyncMerge.merge(local: local, remote: remote, base: base))
        XCTAssertEqual(merged["title"] as? String, "Read more")
        XCTAssertEqual(merged["notes"] as? String, "Second")
        XCTAssertNotNil(SyncMerge.merge(local: ["id": "a", "title": "Read", "updatedAt": 1, "conversionData": NSNull()], remote: ["id": "a", "title": "Read", "updatedAt": 2], base: nil))
        XCTAssertNotNil(SyncMerge.merge(local: ["title": "Gym", "reminders": [1792460000000.0002]], remote: ["title": "Gym", "reminders": [1792460000000.0]], base: nil))
        XCTAssertNil(SyncMerge.merge(local: ["title": "Gym"], remote: ["title": "Walk"], base: ["title": "Read"]))
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
