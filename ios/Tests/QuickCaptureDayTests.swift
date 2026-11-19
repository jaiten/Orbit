import XCTest
@testable import Orbit

final class QuickCaptureDayTests: XCTestCase {
    private var calendar: Calendar {
        var value = Calendar(identifier: .gregorian)
        value.timeZone = TimeZone(secondsFromGMT: 0)!
        return value
    }
    private func date(_ day: Int, _ hour: Int, _ minute: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
    }

    func testCaptureAfterMidnightStaysOnTodayUntilThePlannerBoundary() {
        let now = date(19, 0, 37)
        let selected = QuickAdd.captureDay(initialDate: nil, now: now, calendar: calendar, dayStartMinutes: 120)
        XCTAssertEqual(selected, date(18, 0))
        let parsed = QuickAdd.parse("Minute regression", defaultDay: .day(PlannerLogic.dayKey(selected, calendar: calendar)),
                                    now: DayStart.shifted(now, minutes: 120), calendar: calendar, places: [])
        XCTAssertEqual(parsed.date, "2026-11-18")
        XCTAssertEqual(QuickAdd.captureDay(initialDate: nil, now: date(19, 2), calendar: calendar, dayStartMinutes: 120), date(19, 0))
    }

    func testCaptureRespectsCustomPlannerBoundaries() {
        XCTAssertEqual(QuickAdd.captureDay(initialDate: nil, now: date(19, 3, 30), calendar: calendar, dayStartMinutes: 240), date(18, 0))
        XCTAssertEqual(QuickAdd.captureDay(initialDate: nil, now: date(18, 23, 30), calendar: calendar, dayStartMinutes: -60), date(19, 0))
    }

    func testExplicitCalendarDateIsNeverShiftedByThePlannerBoundary() {
        let selected = date(25, 0)
        XCTAssertEqual(QuickAdd.captureDay(initialDate: selected, now: date(19, 0, 37), calendar: calendar, dayStartMinutes: 120), selected)
    }
}
