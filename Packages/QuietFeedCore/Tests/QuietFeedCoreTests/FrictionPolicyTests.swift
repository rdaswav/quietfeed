import XCTest
@testable import QuietFeedCore

final class FrictionPolicyTests: XCTestCase {
    typealias P = FrictionPolicy

    func testGateTableRowByRow() {
        XCTAssertTrue(P.needsGate(.extendTime))
        XCTAssertTrue(P.needsGate(.pauseFilters))
        XCTAssertTrue(P.needsGate(.raiseBudget(site: "youtube")))
        XCTAssertTrue(P.needsGate(.raiseExtensionLength))
        XCTAssertTrue(P.needsGate(.raiseMaxExtensions))
        XCTAssertTrue(P.needsGate(.raiseMaxFilterPauses))
        XCTAssertTrue(P.needsGate(.shortenCountdown))
        XCTAssertTrue(P.needsGate(.changePhrase))
        XCTAssertTrue(P.needsGate(.changeShieldSelection))
        XCTAssertTrue(P.needsGate(.startPostMode))
        XCTAssertFalse(P.needsGate(.lowerBudget(site: "youtube")))
        XCTAssertFalse(P.needsGate(.lengthenCountdown))
    }

    func testPhraseMatching() {
        let phrase = "I am choosing to scroll"
        XCTAssertTrue(P.phraseMatches(typed: "I am choosing to scroll", phrase: phrase))
        XCTAssertTrue(P.phraseMatches(typed: "i AM Choosing TO scroll", phrase: phrase))
        XCTAssertTrue(P.phraseMatches(typed: "  I am choosing to scroll \n", phrase: phrase))
        XCTAssertFalse(P.phraseMatches(typed: "I am choosing to scrol", phrase: phrase))
        XCTAssertFalse(P.phraseMatches(typed: "I am  choosing to scroll", phrase: phrase), "inner spaces must match")
        XCTAssertFalse(P.phraseMatches(typed: "", phrase: phrase))
        XCTAssertFalse(P.phraseMatches(typed: "", phrase: ""))
    }

    private let base = LimitSettings()

    private func change(_ edit: (inout LimitSettings) -> Void) -> LimitSettings {
        var s = base
        edit(&s)
        return s
    }

    func testRaiseBudgetIsLoosening() {
        let new = change { $0.dailyBudgetMinutesBySite["youtube"] = 30 }
        XCTAssertEqual(P.loosenings(from: base, to: new), [.raiseBudget(site: "youtube")])
        XCTAssertTrue(P.requiresGate(from: base, to: new))
    }

    func testLowerBudgetIsFree() {
        let new = change { $0.dailyBudgetMinutesBySite["youtube"] = 10 }
        XCTAssertEqual(P.loosenings(from: base, to: new), [])
        XCTAssertFalse(P.requiresGate(from: base, to: new))
    }

    func testRemovingTheLimitIsLooseningAndAddingOneIsNot() {
        let off = change { $0.dailyBudgetMinutesBySite["youtube"] = 0 }
        XCTAssertEqual(P.loosenings(from: base, to: off), [.raiseBudget(site: "youtube")])
        XCTAssertEqual(P.loosenings(from: off, to: base), [])
    }

    func testRaiseMaxesAndExtensionLength() {
        XCTAssertEqual(P.loosenings(from: base, to: change { $0.maxExtensionsPerDay = 3 }), [.raiseMaxExtensions])
        XCTAssertEqual(P.loosenings(from: base, to: change { $0.maxFilterPausesPerDay = 2 }), [.raiseMaxFilterPauses])
        XCTAssertEqual(P.loosenings(from: base, to: change { $0.extensionMinutes = 10 }), [.raiseExtensionLength])
    }

    func testLoweringMaxesAndExtensionLengthIsFree() {
        let new = change { $0.maxExtensionsPerDay = 1; $0.maxFilterPausesPerDay = 0; $0.extensionMinutes = 1 }
        XCTAssertEqual(P.loosenings(from: base, to: new), [])
    }

    func testCountdownShorterIsLooseningLongerIsFree() {
        XCTAssertEqual(P.loosenings(from: base, to: change { $0.frictionCountdownSeconds = 10 }), [.shortenCountdown])
        XCTAssertEqual(P.loosenings(from: base, to: change { $0.frictionCountdownSeconds = 60 }), [])
        XCTAssertEqual(P.loosenings(from: base, to: change { $0.frictionCountdownSeconds = 30 }), [])
    }

    func testChangingThePhraseIsLoosening() {
        XCTAssertEqual(P.loosenings(from: base, to: change { $0.frictionPhrase = "ok" }), [.changePhrase])
    }

    func testNoChangeNeedsNoGate() {
        XCTAssertFalse(P.requiresGate(from: base, to: base))
    }

    func testMixedChangeReportsEachLoosening() {
        let new = change {
            $0.dailyBudgetMinutesBySite["instagram"] = 5
            $0.dailyBudgetMinutesBySite["facebook"] = 25
            $0.frictionCountdownSeconds = 45
        }
        XCTAssertEqual(P.loosenings(from: base, to: new), [.raiseBudget(site: "facebook")])
        XCTAssertTrue(P.requiresGate(from: base, to: new))
    }

    func testSettingsDefaultsAndCodable() throws {
        let s = LimitSettings()
        XCTAssertEqual(s.budgetMinutes(site: "instagram"), 20)
        XCTAssertEqual(s.extensionMinutes, 5)
        XCTAssertEqual(s.maxExtensionsPerDay, 2)
        XCTAssertEqual(s.maxFilterPausesPerDay, 1)
        XCTAssertEqual(s.frictionCountdownSeconds, 30)
        XCTAssertEqual(s.frictionPhrase, "I am choosing to scroll")
        XCTAssertEqual(try JSONDecoder().decode(LimitSettings.self, from: JSONEncoder().encode(s)), s)
    }
}
