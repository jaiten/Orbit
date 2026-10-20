import XCTest
import SwiftData
@testable import Orbit

/// The rules in docs/sync-plan.md: all-day tasks and check-ins are floating calendar days,
/// habit reminder times follow local time, and timed tasks are instants.
@MainActor final class TimeZoneTests: XCTestCase {
    private var original = NSTimeZone.default
    override func setUp() { original = NSTimeZone.default }
    override func tearDown() { NSTimeZone.default = original }

    private func travel(to identifier: String) {
        NSTimeZone.default = TimeZone(identifier: identifier)!
        XCTAssertEqual(Calendar.current.timeZone.identifier, identifier, "The test needs Calendar.current to follow the default time zone")
    }
    private func local(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ minute: Int = 0) -> Date {
        Calendar.current.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: minute))!
    }
    private func context() throws -> ModelContext { ModelContext(try Persistence.makeContainer(inMemory: true)) }

    func testAllDayTaskKeepsItsDayWhenTravelling() throws {
        travel(to: "America/Vancouver")
        let context = try context()
        let task = PlannerTask(title: "Renew passport"); task.schedule(day: "2026-10-20")
        context.insert(task); try Mutations.save(context)
        let entry = try XCTUnwrap(context.fetch(FetchDescriptor<SyncEntry>()).first); entry.dirty = false; try context.save()
        travel(to: "Asia/Tokyo")
        XCTAssertEqual(task.day, "2026-10-20")
        try Migrations.run(context)
        XCTAssertEqual(PlannerLogic.dayKey(try XCTUnwrap(task.dueDate)), "2026-10-20", "The cached midnight moves to the new zone")
        XCTAssertFalse(entry.dirty, "Re-anchoring never re-uploads")
        let payload = try SyncRecords.object(try XCTUnwrap(SyncRecords.snapshots(context)["tasks/" + task.id.uuidString.lowercased()]))
        XCTAssertEqual(payload["localDate"] as? String, "2026-10-20")
        XCTAssertTrue(payload["dueDate"] is NSNull)
    }

    func testHabitLoggedLateEveningIsTheSameDayOnAnotherDevice() throws {
        travel(to: "America/Vancouver")
        let phone = try context()
        let habit = Habit(title: "Read"); phone.insert(habit); try Mutations.save(phone)
        try Mutations.log(habit, at: local(2026, 10, 20, 23, 30), in: phone)
        let snapshots = try SyncRecords.snapshots(phone)
        XCTAssertNotNil(snapshots["habit_logs/" + habit.id.uuidString.lowercased() + "-2026-10-20"])
        travel(to: "Europe/London") // Already 07:30 on the 21st there.
        let pc = try context()
        for (key, payload) in snapshots.sorted(by: { $0.key > $1.key }) {
            try SyncRecords.apply(["key": key, "payload": try SyncRecords.object(payload)], context: pc)
        }
        let logs = try pc.fetch(FetchDescriptor<HabitLog>())
        XCTAssertEqual(logs.map(\.dayKey), ["2026-10-20"])
        let copy = try XCTUnwrap(pc.fetch(FetchDescriptor<Habit>()).first)
        XCTAssertTrue(PlannerLogic.checkedToday(copy, logs: logs, at: local(2026, 10, 20, 12)))
        XCTAssertFalse(PlannerLogic.checkedToday(copy, logs: logs, at: local(2026, 10, 21, 12)))
    }

    func testTimedCallShowsAtLocalTimeInAnotherZone() throws {
        travel(to: "America/New_York")
        let laptop = try context()
        let call = PlannerTask(title: "Call with Sam", dueDate: local(2026, 10, 20, 15), hasTime: true)
        laptop.insert(call); try Mutations.save(laptop)
        let key = "tasks/" + call.id.uuidString.lowercased()
        let payload = try SyncRecords.object(try XCTUnwrap(SyncRecords.snapshots(laptop)[key]))
        travel(to: "America/Los_Angeles")
        let phone = try context()
        try SyncRecords.apply(["key": key, "payload": payload], context: phone)
        let copy = try XCTUnwrap(phone.fetch(FetchDescriptor<PlannerTask>()).first)
        XCTAssertEqual(copy.dueDate, call.dueDate, "The same instant")
        XCTAssertEqual(Calendar.current.component(.hour, from: try XCTUnwrap(copy.dueDate)), 12, "3pm in New York is noon in Los Angeles")
        XCTAssertEqual(copy.day, "2026-10-20")
    }

    func testMovingAcrossDaylightSavingKeepsTheWallClockTime() throws {
        travel(to: "America/Vancouver")
        let task = PlannerTask(title: "Swim", dueDate: local(2026, 3, 7, 9), hasTime: true)
        task.reminders = [local(2026, 3, 7, 8, 45)]
        TodayRules.moveToDay(task, day: local(2026, 3, 9, 12)) // Clocks went forward on the 8th.
        XCTAssertEqual(task.day, "2026-03-09")
        XCTAssertEqual(Calendar.current.component(.hour, from: try XCTUnwrap(task.dueDate)), 9)
        XCTAssertEqual(try XCTUnwrap(task.dueDate).timeIntervalSince(task.reminders[0]), 15 * 60)
        XCTAssertEqual(HabitRules.addDays("2026-03-07", 2), "2026-03-09")
    }

    func testHabitReminderFollowsLocalTimeAndTaskReminderKeepsItsInstant() throws {
        travel(to: "America/Vancouver")
        let context = try context()
        let habit = Habit(title: "Stretch"); habit.reminderMinutes = 7 * 60; context.insert(habit)
        let task = PlannerTask(title: "Call", dueDate: local(2026, 10, 21, 15), hasTime: true)
        task.reminders = [local(2026, 10, 21, 14, 50)]; context.insert(task)
        try Mutations.save(context)
        travel(to: "Asia/Tokyo")
        let reminders = try NotificationScheduler.reminders(context: context, now: local(2026, 10, 21, 1))
        let habitReminder = try XCTUnwrap(reminders.first { $0.id.hasPrefix("orbit.habit.") })
        XCTAssertEqual(Calendar.current.component(.hour, from: habitReminder.date), 7, "7am wherever you are")
        XCTAssertTrue(habitReminder.floating)
        let taskReminder = try XCTUnwrap(reminders.first { $0.id.hasPrefix("orbit.task.") })
        XCTAssertEqual(taskReminder.date, task.reminders[0])
        XCTAssertFalse(taskReminder.floating)
    }
}
