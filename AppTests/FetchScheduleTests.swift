import XCTest
@testable import QuietFeed

final class FetchScheduleTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    func testNoPreviousAttemptFetches() {
        XCTAssertTrue(FetchSchedule.shouldFetch(lastAttempt: nil, now: now))
    }

    func testRecentAttemptDoesNotFetch() {
        XCTAssertFalse(FetchSchedule.shouldFetch(lastAttempt: now.addingTimeInterval(-3600), now: now))
    }

    func testExactlySixHoursDoesNotFetchButJustOverDoes() {
        XCTAssertFalse(FetchSchedule.shouldFetch(lastAttempt: now.addingTimeInterval(-6 * 3600), now: now))
        XCTAssertTrue(FetchSchedule.shouldFetch(lastAttempt: now.addingTimeInterval(-6 * 3600 - 1), now: now))
    }

    func testClockMovedBackwardsFetches() {
        XCTAssertTrue(FetchSchedule.shouldFetch(lastAttempt: now.addingTimeInterval(60), now: now))
    }

    func testInfoPlistHasLocalNetworkKeys() {
        XCTAssertFalse((Bundle.main.object(forInfoDictionaryKey: "NSLocalNetworkUsageDescription") as? String ?? "").isEmpty)
        let ats = Bundle.main.object(forInfoDictionaryKey: "NSAppTransportSecurity") as? [String: Any]
        XCTAssertEqual(ats?["NSAllowsLocalNetworking"] as? Bool, true)
    }
}
