import XCTest
import SwiftData
@testable import Orbit

final class DailyPlanningTests: XCTestCase {
    private func at(_ minute: Int) -> Date { Date(timeIntervalSince1970: Double(minute * 60)) }
    func testFitsAroundOverlappingBusyEventsAndExactBoundaries() {
        let busy = [DailyPlanning.Block(start: at(20), end: at(45)), .init(start: at(40), end: at(60)), .init(start: at(100), end: at(120))]
        let items = [DailyPlanning.Item(id: "a", title: "Walk", minutes: 20), .init(id: "b", title: "Read", minutes: 30), .init(id: "c", title: "Call", minutes: 10)]
        let result = DailyPlanning.suggest(items, from: at(0), to: at(120), busy: busy)
        XCTAssertEqual(result.slots.map(\.start), [at(0), at(60), at(90)])
        XCTAssertEqual(result.slots.map(\.end), [at(20), at(90), at(100)])
        XCTAssertTrue(result.unscheduled.isEmpty)
    }
    func testOversizedItemDoesNotHideSmallerItemsOrOverflowWindow() {
        let items = [DailyPlanning.Item(id: "long", title: "Project", minutes: 90), .init(id: "short", title: "Stretch", minutes: 10)]
        let result = DailyPlanning.suggest(items, from: at(0), to: at(30), busy: [])
        XCTAssertEqual(result.slots.map(\.id), ["short"])
        XCTAssertEqual(result.unscheduled.map(\.id), ["long"])
        let blocked = DailyPlanning.suggest(items, from: at(0), to: at(30), busy: [.init(start: at(-10), end: at(40))])
        XCTAssertTrue(blocked.slots.isEmpty)
        XCTAssertEqual(blocked.unscheduled, items)
        XCTAssertEqual(DailyPlanning.suggest(items, from: at(30), to: at(0), busy: []).unscheduled, items)
    }
    func testUnsortedEventsAndInsertedSlotsNeverOverlap() {
        let items = (0..<8).map { DailyPlanning.Item(id: String($0), title: "Task", minutes: 15) }
        let busy = [DailyPlanning.Block(start: at(70), end: at(90)), .init(start: at(10), end: at(35)), .init(start: at(-5), end: at(5))]
        let result = DailyPlanning.suggest(items, from: at(0), to: at(120), busy: busy)
        let blocks = busy + result.slots.map { DailyPlanning.Block(start: $0.start, end: $0.end) }
        for slot in result.slots {
            XCTAssertTrue(slot.start >= at(0) && slot.end <= at(120))
            XCTAssertEqual(blocks.filter { slot.start < $0.end && $0.start < slot.end }.count, 1)
        }
        XCTAssertEqual(result.slots.count + result.unscheduled.count, items.count)
    }
    @MainActor func testRemovedGeneralCheckInIsIgnoredForExistingUsers() throws {
        let defaults = UserDefaults.standard
        let previous = defaults.object(forKey: "generalCheckIn")
        defer { if let previous { defaults.set(previous, forKey: "generalCheckIn") } else { defaults.removeObject(forKey: "generalCheckIn") } }
        defaults.set(true, forKey: "generalCheckIn")
        let context = ModelContext(try Persistence.makeContainer(inMemory: true))
        let task = PlannerTask(title: "Call dentist")
        task.reminders = [Date.now.addingTimeInterval(3600)]
        context.insert(task)
        let reminders = try NotificationScheduler.reminders(context: context)
        XCTAssertEqual(reminders.count, 1)
        XCTAssertTrue(reminders[0].id.hasPrefix("orbit.task."))
        XCTAssertFalse(reminders.contains { $0.id.hasPrefix("orbit.checkin.") })
    }

    func testTaskDateGroupsAreExclusiveAndCompletionWins() {
        let today = "2026-10-22"
        XCTAssertEqual(TaskDateGroup.group(day: today, someday: false, completed: false, today: today), .today)
        XCTAssertEqual(TaskDateGroup.group(day: "2026-10-21", someday: false, completed: false, today: today), .overdue)
        XCTAssertEqual(TaskDateGroup.group(day: "2026-10-23", someday: false, completed: false, today: today), .upcoming)
        XCTAssertEqual(TaskDateGroup.group(day: nil, someday: false, completed: false, today: today), .undated)
        XCTAssertEqual(TaskDateGroup.group(day: nil, someday: true, completed: false, today: today), .someday)
        XCTAssertEqual(TaskDateGroup.group(day: nil, someday: true, completed: true, today: today), .completed)
    }
}
