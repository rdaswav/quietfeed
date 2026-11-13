import XCTest
@testable import QuietFeed

final class OnboardingTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ob-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeModel(suite: String) -> AppModel {
        AppModel(
            defaults: UserDefaults(suiteName: suite)!,
            cacheURL: dir.appendingPathComponent("c.json"),
            usageURL: dir.appendingPathComponent("u.json"),
            limitsURL: dir.appendingPathComponent("l.json"),
            shield: FakeShieldController())
    }

    func testShownOnFirstLaunch() {
        XCTAssertTrue(makeModel(suite: "ob-\(UUID().uuidString)").showOnboarding)
    }

    func testShownOnlyOnce() {
        let suite = "ob-\(UUID().uuidString)"
        let first = makeModel(suite: suite)
        first.completeOnboarding()
        XCTAssertFalse(first.showOnboarding)
        XCTAssertFalse(makeModel(suite: suite).showOnboarding)
    }

    func testBudgetsChosenInOnboardingAreKept() {
        let suite = "ob-\(UUID().uuidString)"
        let model = makeModel(suite: suite)
        var new = model.limits
        new.dailyBudgetMinutesBySite["instagram"] = 10
        model.commitLimits(new)
        XCTAssertEqual(makeModel(suite: suite).limits.budgetMinutes(site: "instagram"), 10)
    }
}
