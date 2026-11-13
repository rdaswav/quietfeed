import XCTest
@testable import QuietFeedCore

final class BudgetEngineTests: XCTestCase {
    private func engine(budget: Int = 20, extMinutes: Int = 5, maxExt: Int = 2, pauses: Int = 1) -> BudgetEngine {
        BudgetEngine(settings: LimitSettings(
            dailyBudgetMinutesBySite: ["youtube": budget], extensionMinutes: extMinutes,
            maxExtensionsPerDay: maxExt, maxFilterPausesPerDay: pauses))
    }

    func testUnlimitedWhenBudgetIsZero() {
        XCTAssertEqual(engine(budget: 0).state(site: "youtube", usedSeconds: 999_999, extensionsUsed: 0), .unlimited)
    }

    func testOkWhenPlentyRemains() {
        XCTAssertEqual(engine().state(site: "youtube", usedSeconds: 0, extensionsUsed: 0), .ok(remaining: 1200))
        XCTAssertEqual(engine().state(site: "youtube", usedSeconds: 600, extensionsUsed: 0), .ok(remaining: 600))
    }

    func testWarningBoundaryAtTwoMinutes() {
        let e = engine()
        XCTAssertEqual(e.state(site: "youtube", usedSeconds: 1200 - 121, extensionsUsed: 0), .ok(remaining: 121))
        XCTAssertEqual(e.state(site: "youtube", usedSeconds: 1200 - 120, extensionsUsed: 0), .warning(remaining: 120))
        XCTAssertEqual(e.state(site: "youtube", usedSeconds: 1200 - 1, extensionsUsed: 0), .warning(remaining: 1))
    }

    func testExhaustedAtAndPastTheBudget() {
        let e = engine()
        XCTAssertEqual(e.state(site: "youtube", usedSeconds: 1200, extensionsUsed: 0), .exhausted(canExtend: true))
        XCTAssertEqual(e.state(site: "youtube", usedSeconds: 5000, extensionsUsed: 0), .exhausted(canExtend: true))
    }

    func testExtensionMaths() {
        let e = engine(budget: 20, extMinutes: 5)
        XCTAssertEqual(e.allowedSeconds(site: "youtube", extensionsUsed: 0), 1200)
        XCTAssertEqual(e.allowedSeconds(site: "youtube", extensionsUsed: 1), 1500)
        XCTAssertEqual(e.allowedSeconds(site: "youtube", extensionsUsed: 2), 1800)
        // After one extension the same usage is no longer exhausted.
        XCTAssertEqual(e.state(site: "youtube", usedSeconds: 1200, extensionsUsed: 1), .ok(remaining: 300))
        XCTAssertEqual(e.state(site: "youtube", usedSeconds: 1500 - 60, extensionsUsed: 1), .warning(remaining: 60))
    }

    func testMaxExtensionsStopsFurtherExtending() {
        let e = engine(maxExt: 2)
        XCTAssertEqual(e.state(site: "youtube", usedSeconds: 1800, extensionsUsed: 2), .exhausted(canExtend: false))
        XCTAssertEqual(e.state(site: "youtube", usedSeconds: 1500, extensionsUsed: 1), .exhausted(canExtend: true))
        XCTAssertEqual(engine(maxExt: 0).state(site: "youtube", usedSeconds: 1200, extensionsUsed: 0),
                       .exhausted(canExtend: false))
    }

    func testMissingSiteUsesDefaultBudget() {
        XCTAssertEqual(engine().state(site: "facebook", usedSeconds: 0, extensionsUsed: 0), .ok(remaining: 1200))
    }

    func testFilterPauseLimit() {
        let e = engine(pauses: 1)
        XCTAssertTrue(e.canPauseFilters(pausesUsed: 0))
        XCTAssertFalse(e.canPauseFilters(pausesUsed: 1))
    }

    func testStateFromLedger() {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("be-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let ledger = UsageLedger(store: JSONFileStore(url: dir.appendingPathComponent("u.json")))
        ledger.addSeconds(1100, site: "youtube")
        XCTAssertEqual(engine().state(site: "youtube", ledger: ledger), .warning(remaining: 100))
        ledger.recordExtension(site: "youtube")
        XCTAssertEqual(engine().state(site: "youtube", ledger: ledger), .ok(remaining: 400))
    }
}
