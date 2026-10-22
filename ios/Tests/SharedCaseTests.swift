import XCTest
import SwiftData
@testable import Orbit

/// Runs the cross-platform case tables in shared/test-cases, the same files the Windows tests read.
final class SharedCaseTests: XCTestCase {
    static func cases(_ name: String) throws -> [[String: Any]] {
        // Simulator tests can read the checked-out repository directly.
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("../../shared/test-cases/\(name).json").standardizedFileURL
        let object = try JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any]
        return try XCTUnwrap(object?["cases"] as? [[String: Any]])
    }

    func testAutomaticIconCasesAndManualChoices() throws {
        for row in try Self.cases("icons") {
            XCTAssertEqual(ItemIcons.suggested(for: row["title"] as! String), row["expect"] as? String)
        }
        XCTAssertEqual(ItemIcons.symbol("leaf", title: "Gym"), "leaf")
        XCTAssertEqual(ItemIcons.symbol("automatic", title: "Gym"), "dumbbell")
        XCTAssertEqual(ItemIcons.symbol("unknown.symbol", title: "Gym"), "checklist")
        XCTAssertEqual(Set(ItemIcons.all.map(\.id)).count, ItemIcons.all.count)
    }

    func testHabitColorCases() throws {
        for c in try Self.cases("habit-colors") {
            XCTAssertEqual(HabitRules.nextColor(c["existing"] as! [String]), c["expect"] as? String, c["name"] as? String ?? "")
        }
    }

    func testHabitCases() throws {
        let cases = try Self.cases("habits")
        XCTAssertFalse(cases.isEmpty)
        for c in cases {
            let name = c["name"] as! String
            let habit = c["habit"] as! [String: Any]
            let rule = habit["frequencyRule"] as! String, target = habit["target"] as! Int
            let counts = (c["logs"] as! [[String: Any]]).reduce(into: [String: Int]()) { $0[$1["dayKey"] as! String, default: 0] += $1["count"] as! Int }
            let day = c["day"] as! String, weekStart = c["weekStart"] as! Int
            let expect = c["expect"] as! [String: Any]
            XCTAssertEqual(HabitRules.due(rule: rule, target: target, counts: counts, day: day, weekStart: weekStart), expect["due"] as? Bool, name)
            XCTAssertEqual(HabitRules.checked(rule: rule, target: target, counts: counts, day: day), expect["checked"] as? Bool, name)
            XCTAssertEqual(HabitRules.periodProgress(rule: rule, counts: counts, day: day, weekStart: weekStart), expect["progress"] as? Int, name)
            XCTAssertEqual(HabitRules.checkedDays(rule: rule, target: target, counts: counts, day: day), expect["lastSeven"] as? Int, name)
        }
    }

    func testTodayCases() throws {
        for c in try Self.cases("today") {
            let name = c["name"] as! String, today = c["today"] as! String
            let day = c["day"] as? String ?? today
            let items = (c["items"] as! [[String: Any]]).map { i in
                (title: i["title"] as! String, item: TodayRules.Item(day: i["day"] as? String, completedDay: i["completedDay"] as? String, someday: i["someday"] as? Bool ?? false))
            }
            XCTAssertEqual(items.filter { TodayRules.onDay($0.item, day: day, today: today) }.map(\.title), c["expect"] as! [String], name)
            XCTAssertEqual(items.filter { TodayRules.isOverdue($0.item, today: today) }.map(\.title), c["overdue"] as! [String], name)
        }
        XCTAssertEqual(TodayRules.overdueLabel("2026-10-20", today: "2026-10-22"), "from Tue")
    }

    func testQuickAddPhrases() throws {
        let url = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../shared/test-cases/quick-add.json").standardizedFileURL
        let table = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        // "now" is local wall-clock time, so the table holds in any time zone.
        let parts = (table["now"] as! String).split(whereSeparator: { "-T:".contains($0) }).map { Int($0)! }
        let calendar = Calendar.current
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: parts[0], month: parts[1], day: parts[2], hour: parts[3], minute: parts[4])))
        for c in table["cases"] as! [[String: Any]] {
            let input = c["input"] as! String
            var defaultDay = DefaultDay.today
            if let key = c["defaultDate"] as? String { defaultDay = key == "undated" ? .undated : .day(key) }
            let result = QuickAdd.parse(input, defaultDay: defaultDay, now: now, calendar: calendar)
            let expect = c["expect"] as! [String: Any]
            XCTAssertEqual(result.kind.rawValue, expect["kind"] as? String, input)
            XCTAssertEqual(result.title, expect["title"] as? String, input)
            XCTAssertEqual(result.time, expect["time"] as? Int, input)
            XCTAssertEqual(result.schedule, expect["schedule"] as? String, input)
            XCTAssertEqual(result.someday, expect["someday"] as? Bool ?? false, input)
            XCTAssertEqual(result.list, expect["list"] as? String, input)
            if result.kind == .task { XCTAssertEqual(result.date, expect["date"] as? String, input) }
        }
        XCTAssertEqual(QuickAdd.describe(QuickAdd.parse("stretch weekdays 7am", now: now), now: now), "Habit · Weekdays · 7:00 AM")
        XCTAssertEqual(QuickAdd.describe(QuickAdd.parse("gym tomorrow 6pm #health", now: now), now: now), "Task · Tomorrow · 6:00 PM · List: health")
        XCTAssertEqual(QuickAdd.describe(QuickAdd.parse("learn piano someday", now: now), now: now), "Someday")
    }

    func testConsistencyCases() throws {
        for c in try Self.cases("consistency") {
            let logs = c["logs"] as! [[String: Any]]
            let habits = (c["habits"] as! [[String: Any]]).map { h in
                HabitRules.Entry(rule: h["frequencyRule"] as! String, target: h["target"] as! Int, createdDay: h["createdDay"] as? String,
                                 counts: logs.filter { $0["habitID"] as? String == h["id"] as? String }.reduce(into: [String: Int]()) { $0[$1["dayKey"] as! String, default: 0] += $1["count"] as! Int })
            }
            XCTAssertEqual(HabitRules.consistency(habits, day: c["day"] as! String), c["expect"] as! Double, accuracy: 1e-9, c["name"] as! String)
        }
    }

    @MainActor func testExportRoundTripAndCSVMatchWindows() throws {
        let folder = URL(fileURLWithPath: #filePath).deletingLastPathComponent().appendingPathComponent("../../shared/test-cases").standardizedFileURL
        let data = try Data(contentsOf: folder.appendingPathComponent("export-sample.json"))
        let sample = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? NSDictionary)
        let original = NSTimeZone.default; defer { NSTimeZone.default = original }
        NSTimeZone.default = TimeZone(identifier: "UTC")! // The CSV has local times; the sample is checked in UTC.
        let records = try PlannerBackup.decode(data)
        let context = ModelContext(try Persistence.makeContainer(inMemory: true))
        for record in records { try SyncRecords.apply(record, context: context) }
        let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        let exported = try PlannerBackup.encode(SyncRecords.snapshots(context), exportedAt: try XCTUnwrap(formatter.date(from: sample["exportedAt"] as! String)))
        XCTAssertEqual(try JSONSerialization.jsonObject(with: exported) as? NSDictionary, sample)
        let csv = try String(contentsOf: folder.appendingPathComponent("export-sample.csv"), encoding: .utf8)
        XCTAssertEqual(PlannerBackup.tasksCSV(records), csv)
        // Importing never silently overwrites: the same file again is all "same"; an edit shows as changed.
        var current = try SyncRecords.snapshots(context)
        XCTAssertEqual(PlannerBackup.plan(current: current, records: records).same.count, records.count)
        let key = records[3]["key"] as! String
        var edited = try SyncRecords.object(current[key]!); edited["title"] = "Edited here"; current[key] = try SyncRecords.json(edited)
        let plan = PlannerBackup.plan(current: current, records: records)
        XCTAssertEqual(plan.changed.map { $0["key"] as! String }, [key])
    }

    func testCalendarArithmeticIgnoresDaylightSaving() {
        XCTAssertEqual(HabitRules.addDays("2026-03-07", 1), "2026-03-08")
        XCTAssertEqual(HabitRules.addDays("2026-11-01", 1), "2026-11-02")
        XCTAssertEqual(HabitRules.addDays("2026-03-01", -1), "2026-02-28")
        XCTAssertEqual(HabitRules.weekday("2026-10-19"), 1, "Monday")
    }
}
