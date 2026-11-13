import XCTest
@testable import QuietFeedCore

final class UsageLedgerTests: XCTestCase {
    private var dir: URL!
    private var current = Date()
    private var calendar: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "Australia/Melbourne")!
        return c
    }()

    override func setUp() {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("ledger-\(UUID().uuidString)")
        current = date(2026, 11, 13, 10, 0)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func date(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int, _ s: Int = 0) -> Date {
        calendar.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min, second: s))!
    }

    private func makeLedger() -> UsageLedger {
        let store = JSONFileStore(url: dir.appendingPathComponent("usage.json"))
        return UsageLedger(store: store, clock: Clock(now: { self.current }, calendar: calendar))
    }

    func testAddingSeconds() {
        let l = makeLedger()
        XCTAssertEqual(l.seconds(site: "youtube"), 0)
        l.addSeconds(1, site: "youtube")
        l.addSeconds(59, site: "youtube")
        l.addSeconds(5, site: "instagram")
        l.addSeconds(0, site: "instagram")
        l.addSeconds(-3, site: "instagram")
        XCTAssertEqual(l.seconds(site: "youtube"), 60)
        XCTAssertEqual(l.seconds(site: "instagram"), 5)
        XCTAssertEqual(l.today.day, "2026-11-13")
    }

    func testPersistenceAcrossInstances() {
        let a = makeLedger()
        a.addSeconds(90, site: "facebook")
        a.flush()
        let b = makeLedger()
        XCTAssertEqual(b.seconds(site: "facebook"), 90)
    }

    func testUnflushedSecondsAreNotPersisted() {
        let a = makeLedger()
        a.addSeconds(90, site: "facebook")
        XCTAssertEqual(makeLedger().seconds(site: "facebook"), 0)
    }

    func testRolloverAtLocalMidnight() {
        current = date(2026, 11, 13, 23, 59, 58)
        let l = makeLedger()
        l.addSeconds(100, site: "youtube")
        current = date(2026, 11, 14, 0, 0, 1)
        XCTAssertEqual(l.today.day, "2026-11-14")
        XCTAssertEqual(l.seconds(site: "youtube"), 0)
        l.addSeconds(7, site: "youtube")
        XCTAssertEqual(l.seconds(site: "youtube"), 7)
        XCTAssertEqual(l.history.map(\.day), ["2026-11-13", "2026-11-14"])
        XCTAssertEqual(l.history.first?.secondsBySite["youtube"], 100)
    }

    func testMidnightUsesTheCalendarTimeZoneNotUTC() {
        // 2026-11-13 23:30 in Melbourne is still the 13th locally, though it is the 13th 12:30 UTC.
        current = date(2026, 11, 13, 23, 30)
        XCTAssertEqual(makeLedger().today.day, "2026-11-13")
        current = date(2026, 11, 14, 0, 30)
        XCTAssertEqual(makeLedger().today.day, "2026-11-14")
    }

    func testFourteenDayRetention() {
        // Create usage on 20 consecutive days.
        // Walk day by day from a fixed start using Calendar. Time starts there, not at setUp's date.
        let start = date(2026, 10, 20, 12, 0)
        current = start
        let l = makeLedger()
        for offset in 0..<20 {
            current = calendar.date(byAdding: .day, value: offset, to: start)!
            l.addSeconds(10, site: "youtube")
        }
        l.flush()
        let days = makeLedger().history.map(\.day)
        XCTAssertEqual(days.count, 14)
        XCTAssertEqual(days.last, "2026-11-08")
        XCTAssertEqual(days.first, "2026-10-26")
    }

    func testCountingExtensionsAndFilterPauses() {
        let l = makeLedger()
        l.recordExtension(site: "youtube")
        l.recordExtension(site: "youtube")
        l.recordFilterPause(site: "youtube")
        l.recordExtension(site: "facebook")
        XCTAssertEqual(l.extensions(site: "youtube"), 2)
        XCTAssertEqual(l.filterPauses(site: "youtube"), 1)
        XCTAssertEqual(l.extensions(site: "facebook"), 1)
        XCTAssertEqual(l.filterPauses(site: "facebook"), 0)
        // Extensions and pauses persist at once.
        let b = makeLedger()
        XCTAssertEqual(b.extensions(site: "youtube"), 2)
        XCTAssertEqual(b.filterPauses(site: "youtube"), 1)
        // And reset on a new day.
        current = date(2026, 11, 14, 9, 0)
        XCTAssertEqual(b.extensions(site: "youtube"), 0)
        XCTAssertEqual(b.filterPauses(site: "youtube"), 0)
    }
}
