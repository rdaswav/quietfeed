import XCTest
import QuietFeedCore
@testable import QuietFeed

final class ShieldReconcilerTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    private func fake(_ auth: ShieldAuthorization = .approved, selection: Int = 3) -> FakeShieldController {
        FakeShieldController(authorization: auth, selectionCount: selection, clock: { self.now })
    }

    func testSelectionPresentAndShieldEmptyApplies() {
        let s = fake()
        XCTAssertEqual(ShieldReconciler.reconcile(s, enabled: true, now: now), .applied)
        XCTAssertTrue(s.isShieldApplied)
    }

    func testPostModeActiveLeavesTheShieldAlone() throws {
        let s = fake()
        try s.startPostMode(minutes: 15)
        XCTAssertEqual(ShieldReconciler.reconcile(s, enabled: true, now: now.addingTimeInterval(60)), .none)
        XCTAssertFalse(s.isShieldApplied)
    }

    func testAfterPostModeEndsTheShieldComesBack() throws {
        let s = fake()
        try s.startPostMode(minutes: 15)
        XCTAssertEqual(ShieldReconciler.reconcile(s, enabled: true, now: now.addingTimeInterval(16 * 60)), .applied)
        XCTAssertTrue(s.isShieldApplied)
    }

    func testNotApprovedDoesNothing() {
        for auth in [ShieldAuthorization.notDetermined, .denied] {
            let s = fake(auth)
            XCTAssertEqual(ShieldReconciler.reconcile(s, enabled: true, now: now), .none)
            XCTAssertFalse(s.isShieldApplied)
        }
    }

    func testNoSelectionDoesNothing() {
        let s = fake(selection: 0)
        XCTAssertEqual(ShieldReconciler.reconcile(s, enabled: true, now: now), .none)
        XCTAssertFalse(s.isShieldApplied)
    }

    func testAlreadyAppliedDoesNothing() {
        let s = fake()
        s.apply()
        XCTAssertEqual(ShieldReconciler.reconcile(s, enabled: true, now: now), .none)
    }

    func testSwitchedOffClearsAShieldThatIsStillUp() {
        let s = fake()
        s.apply()
        XCTAssertEqual(ShieldReconciler.reconcile(s, enabled: false, now: now), .cleared)
        XCTAssertFalse(s.isShieldApplied)
    }

    func testSwitchedOffWithNoShieldDoesNothing() {
        XCTAssertEqual(ShieldReconciler.reconcile(fake(), enabled: false, now: now), .none)
    }
}

final class ShieldModelTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("sh-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeModel(_ shield: ShieldController, suite: String = "sh-\(UUID().uuidString)") -> AppModel {
        AppModel(
            defaults: UserDefaults(suiteName: suite)!,
            cacheURL: dir.appendingPathComponent("c.json"),
            usageURL: dir.appendingPathComponent("u.json"),
            limitsURL: dir.appendingPathComponent("l.json"),
            shield: shield)
    }

    func testRequestingAccessUpdatesTheStatus() async {
        let model = makeModel(FakeShieldController())
        XCTAssertEqual(model.shieldAuthorization, .notDetermined)
        await model.requestShieldAccess()
        XCTAssertEqual(model.shieldAuthorization, .approved)
    }

    func testTurningOnAppliesAndTurningOffClears() {
        let s = FakeShieldController(authorization: .approved, selectionCount: 2)
        let model = makeModel(s)
        model.setShieldEnabled(true)
        XCTAssertTrue(s.isShieldApplied)
        model.setShieldEnabled(false)
        XCTAssertFalse(s.isShieldApplied)
    }

    func testTheChoiceToShieldSurvivesARelaunch() {
        let suite = "sh-\(UUID().uuidString)"
        makeModel(FakeShieldController(authorization: .approved, selectionCount: 1), suite: suite).setShieldEnabled(true)
        let again = makeModel(FakeShieldController(authorization: .approved, selectionCount: 1), suite: suite)
        XCTAssertTrue(again.shieldEnabled)
    }

    func testForegroundReconcileRestoresAShieldThatWentMissing() {
        let s = FakeShieldController(authorization: .approved, selectionCount: 2)
        let model = makeModel(s)
        model.setShieldEnabled(true)
        s.clear()
        XCTAssertEqual(model.reconcileShield(), .applied)
        XCTAssertTrue(s.isShieldApplied)
    }
}

final class PostModeModelTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("pm-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeModel(_ shield: ShieldController) -> AppModel {
        AppModel(
            defaults: UserDefaults(suiteName: "pm-\(UUID().uuidString)")!,
            cacheURL: dir.appendingPathComponent("c.json"),
            usageURL: dir.appendingPathComponent("u.json"),
            limitsURL: dir.appendingPathComponent("l.json"),
            shield: shield)
    }

    func testPostModeLiftsTheShieldAndShowsAnEndTime() {
        let s = FakeShieldController(authorization: .approved, selectionCount: 2)
        let model = makeModel(s)
        model.setShieldEnabled(true)
        XCTAssertTrue(s.isShieldApplied)
        XCTAssertNil(model.postModeEndsAt)
        XCTAssertTrue(model.startPostMode())
        XCTAssertFalse(s.isShieldApplied)
        let ends = try! XCTUnwrap(model.postModeEndsAt)
        XCTAssertEqual(ends.timeIntervalSinceNow, Double(AppModel.postModeMinutes * 60), accuracy: 5)
    }

    func testForegroundDuringPostModeLeavesTheShieldDown() {
        let s = FakeShieldController(authorization: .approved, selectionCount: 2)
        let model = makeModel(s)
        model.setShieldEnabled(true)
        model.startPostMode()
        XCTAssertEqual(model.reconcileShield(), .none)
        XCTAssertFalse(s.isShieldApplied)
    }

    func testAFailedPostModeKeepsTheShieldUp() {
        let s = ThrowingShield()
        let model = makeModel(s)
        model.setShieldEnabled(true)
        XCTAssertFalse(model.startPostMode())
        XCTAssertTrue(s.isShieldApplied)
    }

    func testTurningTheShieldOffTellsTheController() {
        let s = FakeShieldController(authorization: .approved, selectionCount: 1)
        let model = makeModel(s)
        model.setShieldEnabled(true)
        XCTAssertTrue(s.enabled)
        model.setShieldEnabled(false)
        XCTAssertFalse(s.enabled)
    }
}

private final class ThrowingShield: ShieldController {
    var authorization: ShieldAuthorization { .approved }
    func requestAuthorization() async throws {}
    var hasSelection: Bool { true }
    var selectionCount: Int { 1 }
    private(set) var isShieldApplied = false
    func apply() { isShieldApplied = true }
    func clear() { isShieldApplied = false }
    func setEnabled(_ on: Bool) {}
    func startPostMode(minutes: Int) throws { throw ShieldError.unavailable }
    var postModeEndsAt: Date? { nil }
}
