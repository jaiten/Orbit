import XCTest
@testable import Orbit

final class SomedayRulesTests: XCTestCase {
    func testCalendarAbsenceNeedsAvailableCalendarData() {
        let dad = SomedayRules.Rule(tag: "dads", trigger: .event, calendar: "Family", title: "Kidz @ James")
        let mum = SomedayRules.Rule(tag: "mum", trigger: .noEvent, calendar: dad.calendar, title: dad.title)
        XCTAssertTrue(dad.matches("2026-11-18", eventTitles: ["Pickup: kidz @ james"]))
        XCTAssertFalse(mum.matches("2026-11-18", eventTitles: [dad.title]))
        XCTAssertTrue(mum.matches("2026-11-18", eventTitles: []))
        XCTAssertFalse(mum.matches("2026-11-18", eventTitles: nil))
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

    func testTaggedCaptureStaysInSomedayEvenWithALegacyPlaceRule() {
        XCTAssertEqual(SomedayRules.tags(in: "Email me@home, then pack @DADS."), ["dads"])
        let dad = SomedayRules.Rule(tag: "dads", trigger: .event, calendar: "Family", title: "Kidz @ James")
        let result = QuickAdd.parse("Pack @dads", places: [.init(name: "dads", days: [3])], visibilityRules: [dad])
        XCTAssertTrue(result.someday)
        XCTAssertNil(result.date)
        XCTAssertEqual(result.title, "Pack @dads")
    }
}
