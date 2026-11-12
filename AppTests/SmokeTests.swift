import XCTest
@testable import QuietFeed

final class SmokeTests: XCTestCase {
    func testBundleLoads() {
        XCTAssertNotNil(Bundle.main.bundleIdentifier)
    }
}
