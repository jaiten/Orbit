import XCTest
@testable import Orbit

final class SomedayRulesTests: XCTestCase {
    func testCalendarAbsenceNeedsAvailableCalendarData() {
        let office = SomedayRules.Rule(tag: "office", trigger: .event, calendar: "Work", title: "Office day")
        let home = SomedayRules.Rule(tag: "home", trigger: .noEvent, calendar: office.calendar, title: office.title)
        XCTAssertTrue(office.matches("2026-11-18", eventTitles: ["Team office day"]))
        XCTAssertFalse(home.matches("2026-11-18", eventTitles: [office.title]))
        XCTAssertTrue(home.matches("2026-11-18", eventTitles: []))
        XCTAssertFalse(home.matches("2026-11-18", eventTitles: nil))
    }

    func testCalendarDayRecurrenceAndRanges() {
        let weekly = SomedayRules.Rule(tag: "school", trigger: .weeks, start: "2026-03-01", interval: 2)
        XCTAssertTrue(weekly.matches("2026-03-15", eventTitles: nil))
        XCTAssertFalse(weekly.matches("2026-03-08", eventTitles: nil))
        let monthly = SomedayRules.Rule(tag: "school", trigger: .months, start: "2026-01-31", interval: 2)
        XCTAssertFalse(monthly.matches("2026-02-28", eventTitles: nil))
        XCTAssertTrue(monthly.matches("2026-03-31", eventTitles: nil))
        let range = SomedayRules.Rule(tag: "school", trigger: .dates, start: "2026-03-01", end: "2026-03-08")
        XCTAssertTrue(range.matches("2026-03-08", eventTitles: nil))
        XCTAssertFalse(range.matches("2026-03-09", eventTitles: nil))
    }

    func testTaggedCaptureStaysInSomeday() {
        XCTAssertEqual(SomedayRules.tags(in: "Email me@home, then pack @OFFICE."), ["office"])
        let office = SomedayRules.Rule(tag: "office", trigger: .event, calendar: "Work", title: "Office day")
        let result = QuickAdd.parse("Pack laptop @office", visibilityRules: [office])
        XCTAssertTrue(result.someday)
        XCTAssertNil(result.date)
        XCTAssertEqual(result.title, "Pack laptop @office")
    }
}
