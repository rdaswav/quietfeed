import XCTest
@testable import QuietFeedCore

final class PlaceholderTests: XCTestCase {
    func testName() {
        XCTAssertEqual(QuietFeedCore.name, "QuietFeedCore")
    }
}
