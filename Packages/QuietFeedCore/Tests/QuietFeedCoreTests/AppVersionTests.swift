import XCTest
@testable import QuietFeedCore

final class AppVersionTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(AppVersion.parse("1"), [1])
        XCTAssertEqual(AppVersion.parse("1.2"), [1, 2])
        XCTAssertEqual(AppVersion.parse("1.2.3"), [1, 2, 3])
        for bad in ["", "a", "1.", ".1", "1..2", "1.2.3.4", "1.-2", "+1", "1.2b", " 1"] {
            XCTAssertNil(AppVersion.parse(bad), bad)
        }
    }

    func testSatisfies() {
        XCTAssertTrue(AppVersion.satisfies(current: "1.4", required: "1.4.0"))
        XCTAssertTrue(AppVersion.satisfies(current: "1.4.1", required: "1.4"))
        XCTAssertTrue(AppVersion.satisfies(current: "2", required: "1.9.9"))
        XCTAssertFalse(AppVersion.satisfies(current: "1.4", required: "1.4.1"))
        XCTAssertFalse(AppVersion.satisfies(current: "1.10", required: "2"))
        XCTAssertTrue(AppVersion.satisfies(current: "1.10", required: "1.9"))
    }

    func testAnUnreadableVersionNeverLetsAPackIn() {
        XCTAssertFalse(AppVersion.satisfies(current: "banana", required: "1.0"))
        XCTAssertFalse(AppVersion.satisfies(current: "1.0", required: "banana"))
    }
}
