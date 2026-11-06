import XCTest
@testable import Orbit

final class NoteDateGroupTests: XCTestCase {
    func testGroupsFollowAppleNotes() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let now = calendar.date(from: DateComponents(year: 2026, month: 11, day: 6, hour: 15))!
        func ago(_ days: Int) -> Date { calendar.date(byAdding: .day, value: -days, to: now)! }
        func title(_ date: Date) -> String { NoteDateGroup.title(for: date, now: now, calendar: calendar) }
        XCTAssertEqual(title(now), "Today")
        XCTAssertEqual(title(ago(1)), "Yesterday")
        XCTAssertEqual(title(ago(5)), "Previous 7 Days")
        XCTAssertEqual(title(ago(20)), "Previous 30 Days")
        XCTAssertEqual(calendar.component(.month, from: ago(70)), 8)
        XCTAssertEqual(title(ago(400)), "2025")
        let groups = NoteDateGroup.groups([0, 0, 1, 5, 6], date: { ago($0) }, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.title), ["Today", "Yesterday", "Previous 7 Days"])
        XCTAssertEqual(groups.map(\.items.count), [2, 1, 2])
    }
}
