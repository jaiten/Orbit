import XCTest
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

    func testCalendarArithmeticIgnoresDaylightSaving() {
        XCTAssertEqual(HabitRules.addDays("2026-03-07", 1), "2026-03-08")
        XCTAssertEqual(HabitRules.addDays("2026-11-01", 1), "2026-11-02")
        XCTAssertEqual(HabitRules.addDays("2026-03-01", -1), "2026-02-28")
        XCTAssertEqual(HabitRules.weekday("2026-10-19"), 1, "Monday")
    }
}
