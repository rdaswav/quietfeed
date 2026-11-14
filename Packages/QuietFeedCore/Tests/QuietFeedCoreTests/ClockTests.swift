import XCTest
@testable import QuietFeedCore

final class ClockTests: XCTestCase {
    private var cal: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func date(_ s: String) -> Date {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime]
        return f.date(from: s)!
    }

    func testMidnightDayIsUnchangedWhenTheStartHourIsZero() {
        let clock = Clock(calendar: cal)
        XCTAssertEqual(clock.dayString(for: date("2026-11-14T00:30:00Z")), "2026-11-14")
        XCTAssertEqual(clock.dayString(for: date("2026-11-14T23:59:00Z")), "2026-11-14")
    }

    func testADayStartingAtSixIncludesTheSmallHoursOfTheNextCalendarDay() {
        let clock = Clock(calendar: cal, dayStartHour: 6)
        XCTAssertEqual(clock.dayString(for: date("2026-11-14T05:59:00Z")), "2026-11-13")
        XCTAssertEqual(clock.dayString(for: date("2026-11-14T06:00:00Z")), "2026-11-14")
        XCTAssertEqual(clock.dayString(for: date("2026-11-15T01:30:00Z")), "2026-11-14")
    }

    func testNextResetIsTheNextSixAm() {
        let clock = Clock(calendar: cal, dayStartHour: 6)
        XCTAssertEqual(clock.nextReset(after: date("2026-11-14T22:00:00Z")), date("2026-11-15T06:00:00Z"))
        XCTAssertEqual(clock.nextReset(after: date("2026-11-15T02:00:00Z")), date("2026-11-15T06:00:00Z"))
        XCTAssertEqual(clock.nextReset(after: date("2026-11-15T06:00:00Z")), date("2026-11-16T06:00:00Z"))
    }

    func testTheRealClockResetsAtSix() {
        XCTAssertEqual(Clock.system.dayStartHour, 6)
        XCTAssertEqual(Clock.defaultDayStartHour, 6)
    }

    func testTheStartHourIsKeptInRange() {
        XCTAssertEqual(Clock(dayStartHour: 40).dayStartHour, 23)
        XCTAssertEqual(Clock(dayStartHour: -3).dayStartHour, 0)
    }
}
