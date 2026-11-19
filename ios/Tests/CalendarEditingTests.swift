import XCTest
import EventKit
@testable import Orbit

@MainActor final class CalendarEditingTests: XCTestCase {
    func testCalendarEditPreservesLocationsAndMinutePrecision() throws {
        let store = EKEventStore()
        let event = EKEvent(eventStore: store)
        event.title = "Visit"
        event.location = "123 Main Street"
        event.startDate = Date(timeIntervalSince1970: 1_800_000_037)
        event.endDate = event.startDate.addingTimeInterval(67 * 60)
        let start = Date(timeIntervalSince1970: 1_800_000_037)
        CalendarShare.edit(["title": "Renamed", "allDay": false, "start": start.timeIntervalSince1970 * 1000, "end": start.addingTimeInterval(67 * 60).timeIntervalSince1970 * 1000], event: event)
        XCTAssertEqual(event.location, "123 Main Street")
        XCTAssertEqual(event.startDate, start)
        XCTAssertEqual(event.endDate.timeIntervalSince(start), 67 * 60, accuracy: 1)
        CalendarShare.edit(["location": "New address"], event: event)
        XCTAssertEqual(event.location, "New address")
        CalendarShare.edit(["location": ""], event: event)
        XCTAssertEqual(event.location ?? "", "")
    }

    func testMissingCalendarReferenceReportsFailureInsteadOfDroppingRequest() {
        XCTAssertThrowsError(try CalendarShare.apply(["kind": "edit", "location": "New address"], to: [:], store: EKEventStore()))
    }
}
