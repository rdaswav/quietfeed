import XCTest
import QuietFeedCore
@testable import QuietFeed

final class RulesSourceTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rs-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeModel(defaults: UserDefaults) -> AppModel {
        AppModel(
            defaults: defaults,
            cacheURL: dir.appendingPathComponent("c.json"),
            usageURL: dir.appendingPathComponent("u.json"),
            limitsURL: dir.appendingPathComponent("l.json"),
            shield: FakeShieldController())
    }

    private func fresh() -> UserDefaults { UserDefaults(suiteName: "rs-\(UUID().uuidString)")! }

    func testAFreshInstallUsesTheOfficialSource() {
        let model = makeModel(defaults: fresh())
        XCTAssertFalse(model.usesCustomRules)
        XCTAssertEqual(model.serverURLText, "")
    }

    func testADeviceWithASavedAddressMigratesToACustomServer() {
        let d = fresh()
        d.set("http://your-server:8787/rulepack.json", forKey: "rules.serverURL")
        let model = makeModel(defaults: d)
        XCTAssertTrue(model.usesCustomRules)
        XCTAssertEqual(model.serverURLText, "http://your-server:8787/rulepack.json")
    }

    func testChoosingCustomNeedsAValidAddress() {
        let model = makeModel(defaults: fresh())
        XCTAssertFalse(model.setServerURL("not an address"))
        XCTAssertFalse(model.usesCustomRules)
        XCTAssertTrue(model.setServerURL("https://rules.example.test/rulepack.json"))
        XCTAssertTrue(model.usesCustomRules)
    }

    func testSwitchingToOfficialForgetsTheCustomAddress() {
        let d = fresh()
        d.set("http://your-server:8787/rulepack.json", forKey: "rules.serverURL")
        let model = makeModel(defaults: d)
        model.useOfficialRules()
        XCTAssertFalse(model.usesCustomRules)
        XCTAssertEqual(model.serverURLText, "")
        XCTAssertNil(d.string(forKey: "rules.serverURL"))
        // And it stays official after a relaunch.
        XCTAssertFalse(makeModel(defaults: d).usesCustomRules)
    }

    func testOfficialUpdatesAreReportedOffWhileThereIsNoKey() {
        XCTAssertEqual(makeModel(defaults: fresh()).officialRulesAreOn, !OfficialRules.publicKeys.isEmpty)
    }
}
