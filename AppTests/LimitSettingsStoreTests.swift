import XCTest
import QuietFeedCore
@testable import QuietFeed

final class LimitSettingsStoreTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ls-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeModel() -> AppModel {
        AppModel(
            defaults: UserDefaults(suiteName: "ls-\(UUID().uuidString)")!,
            cacheURL: dir.appendingPathComponent("c.json"),
            usageURL: dir.appendingPathComponent("u.json"),
            limitsURL: dir.appendingPathComponent("limits.json"))
    }

    func testDefaultsWhenNothingSaved() {
        XCTAssertEqual(makeModel().limits, LimitSettings())
    }

    func testTighteningAppliesAtOnceAndPersistsAcrossRelaunch() {
        let a = makeModel()
        var new = a.limits
        new.dailyBudgetMinutesBySite["youtube"] = 10
        new.frictionCountdownSeconds = 60
        XCTAssertEqual(a.proposeLimits(new), .applied)
        XCTAssertEqual(a.limits.budgetMinutes(site: "youtube"), 10)
        let b = makeModel()
        XCTAssertEqual(b.limits, new)
    }

    func testLooseningIsHeldUntilCommittedThenPersists() {
        let a = makeModel()
        var new = a.limits
        new.dailyBudgetMinutesBySite["youtube"] = 45
        XCTAssertEqual(a.proposeLimits(new), .needsGate)
        XCTAssertEqual(a.limits.budgetMinutes(site: "youtube"), 20, "not applied before the gate")
        XCTAssertEqual(makeModel().limits.budgetMinutes(site: "youtube"), 20)
        a.commitLimits(new)
        XCTAssertEqual(a.limits.budgetMinutes(site: "youtube"), 45)
        XCTAssertEqual(makeModel().limits.budgetMinutes(site: "youtube"), 45)
    }

    func testEachLooseningKindNeedsTheGate() {
        let m = makeModel()
        let base = m.limits
        var raiseMax = base; raiseMax.maxExtensionsPerDay += 1
        var shorter = base; shorter.frictionCountdownSeconds = 10
        var phrase = base; phrase.frictionPhrase = "ok"
        var noLimit = base; noLimit.dailyBudgetMinutesBySite["facebook"] = 0
        for new in [raiseMax, shorter, phrase, noLimit] {
            XCTAssertEqual(m.proposeLimits(new), .needsGate)
        }
        XCTAssertEqual(m.limits, base)
    }

    func testUnchangedIsNoOp() {
        let m = makeModel()
        XCTAssertEqual(m.proposeLimits(m.limits), .unchanged)
    }
}
