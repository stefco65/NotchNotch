import Foundation
import XCTest
@testable import NotchNook

@MainActor
final class CalendarStoreTests: XCTestCase {
    func testCenteredDatesContainThreeDaysOnEitherSide() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        let selected = try XCTUnwrap(
            ISO8601DateFormatter().date(from: "2026-08-09T12:00:00Z")
        )

        let dates = CalendarStore.centeredDates(
            containing: selected,
            calendar: calendar
        )

        XCTAssertEqual(dates.count, 7)
        XCTAssertTrue(calendar.isDate(dates[3], inSameDayAs: selected))
        XCTAssertEqual(calendar.dateComponents([.day], from: dates[0], to: dates[6]).day, 6)
    }
}
