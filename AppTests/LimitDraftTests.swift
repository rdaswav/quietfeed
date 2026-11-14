import XCTest
import QuietFeedCore
@testable import QuietFeed

final class LimitDraftTests: XCTestCase {
    private var dir: URL!

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ld-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func makeModel() -> AppModel {
        AppModel(
            defaults: UserDefaults(suiteName: "ld-\(UUID().uuidString)")!,
            cacheURL: dir.appendingPathComponent("c.json"),
            usageURL: dir.appendingPathComponent("u.json"),
            limitsURL: dir.appendingPathComponent("l.json"),
            shield: FakeShieldController())
    }

    func testManyTapsOnTheCountdownStepperAreOneWaitingChange() {
        let model = makeModel()
        let saved = model.limits.frictionCountdownSeconds
        var draft = LimitDraft()
        for _ in 0..<4 { draft.edit({ $0.frictionCountdownSeconds -= 5 }, model: model) }
        XCTAssertTrue(draft.hasPending)
        XCTAssertEqual(draft.waitingCount(from: model.limits), 1)
        XCTAssertEqual(draft.working(from: model.limits).frictionCountdownSeconds, saved - 20)
        XCTAssertEqual(model.limits.frictionCountdownSeconds, saved, "nothing is saved until the gate is passed")
    }

    func testOneGateAppliesEveryWaitingChange() {
        let model = makeModel()
        var draft = LimitDraft()
        draft.edit({ $0.frictionCountdownSeconds -= 10 }, model: model)
        draft.edit({ $0.dailyBudgetMinutesBySite["instagram"] = 60 }, model: model)
        draft.edit({ $0.maxExtensionsPerDay += 1 }, model: model)
        XCTAssertEqual(draft.waitingCount(from: model.limits), 3)
        let expected = draft.working(from: model.limits)
        draft.applyPending(to: model)
        XCTAssertFalse(draft.hasPending)
        XCTAssertEqual(model.limits, expected)
    }

    func testTighteningStillAppliesAtOnce() {
        let model = makeModel()
        var draft = LimitDraft()
        draft.edit({ $0.dailyBudgetMinutesBySite["instagram"] = 10 }, model: model)
        XCTAssertFalse(draft.hasPending)
        XCTAssertEqual(model.limits.budgetMinutes(site: "instagram"), 10)
    }

    func testUndoingTheLooseningClearsTheWaitingChange() {
        let model = makeModel()
        var draft = LimitDraft()
        draft.edit({ $0.frictionCountdownSeconds -= 5 }, model: model)
        XCTAssertTrue(draft.hasPending)
        draft.edit({ $0.frictionCountdownSeconds += 5 }, model: model)
        XCTAssertFalse(draft.hasPending)
    }

    func testDiscardDropsWaitingChangesAndSavesNothing() {
        let model = makeModel()
        let before = model.limits
        var draft = LimitDraft()
        draft.edit({ $0.frictionCountdownSeconds -= 5 }, model: model)
        draft.discard()
        XCTAssertFalse(draft.hasPending)
        XCTAssertEqual(model.limits, before)
        XCTAssertEqual(draft.working(from: model.limits), before)
    }

    func testATighteningMadeWhileChangesAreWaitingWaitsWithThem() {
        let model = makeModel()
        var draft = LimitDraft()
        draft.edit({ $0.frictionCountdownSeconds -= 5 }, model: model)
        draft.edit({ $0.dailyBudgetMinutesBySite["youtube"] = 5 }, model: model)
        XCTAssertTrue(draft.hasPending)
        XCTAssertEqual(model.limits.budgetMinutes(site: "youtube"), LimitSettings.defaultBudgetMinutes)
        draft.applyPending(to: model)
        XCTAssertEqual(model.limits.budgetMinutes(site: "youtube"), 5)
    }
}
