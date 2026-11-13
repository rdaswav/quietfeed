import XCTest
import QuietFeedCore
@testable import QuietFeed

final class UsageCountingTests: XCTestCase {
    func testTicksUseUpTheBudgetAndExtensionsRestoreIt() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("uc-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = AppModel(
            defaults: UserDefaults(suiteName: "uc-\(UUID().uuidString)")!,
            cacheURL: dir.appendingPathComponent("c.json"),
            usageURL: dir.appendingPathComponent("u.json"))
        XCTAssertEqual(model.budgetState(for: "youtube"), .ok(remaining: 1200))
        for _ in 0..<1200 { model.tick(siteId: "youtube") }
        XCTAssertEqual(model.budgetState(for: "youtube"), .exhausted(canExtend: true))
        XCTAssertEqual(model.extensionsLeft(for: "youtube"), 2)
        model.grantExtension(siteId: "youtube")
        XCTAssertEqual(model.budgetState(for: "youtube"), .ok(remaining: 300))
        XCTAssertEqual(model.extensionsLeft(for: "youtube"), 1)
        XCTAssertTrue(model.canPauseFilters(for: "youtube"))
        model.recordFilterPause(siteId: "youtube")
        XCTAssertFalse(model.canPauseFilters(for: "youtube"))
        // Other sites are untouched.
        XCTAssertEqual(model.budgetState(for: "instagram"), .ok(remaining: 1200))
    }

    func testTimeText() {
        XCTAssertEqual(TimeText.clock(842), "14:02")
        XCTAssertEqual(TimeText.clock(-5), "0:00")
        XCTAssertEqual(TimeText.minutes(841), "15 min")
        XCTAssertEqual(TimeText.minutes(60), "1 min")
        XCTAssertEqual(TimeText.minutes(1), "1 min")
    }
}
