import XCTest
@testable import QuietFeedCore

final class RuleStoreTests: XCTestCase {
    private struct FakeFetcher: RuleFetching {
        var result: Result<Data, Error>
        func fetch(url: URL) async throws -> Data { try result.get() }
    }
    private struct Boom: Error {}

    private var dir: URL!

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rulestore-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func pack(_ version: Int) -> RulePack {
        let site = SiteRules(id: "youtube", name: "YouTube", homeURL: "https://m.youtube.com/",
                             allowedHosts: ["youtube.com"], hideSelectors: ["v\(version)"])
        return RulePack(schemaVersion: 1, packVersion: version, updated: "2026-11-13", sites: [site])
    }

    private func data(_ version: Int) -> Data { try! JSONEncoder().encode(pack(version)) }

    private var cache: JSONFileStore { JSONFileStore(url: dir.appendingPathComponent("rulepack.cache.json")) }

    private func store(bundled: Int = 2, fetch: Result<Data, Error> = .failure(Boom())) -> RuleStore {
        RuleStore(bundled: pack(bundled), cache: cache, fetcher: FakeFetcher(result: fetch),
                  now: { Date(timeIntervalSince1970: 1000) })
    }

    func testBundledOnly() {
        let s = store()
        XCTAssertEqual(s.activePack.packVersion, 2)
        XCTAssertEqual(s.status, RuleStore.Status(source: .bundled, packVersion: 2, lastFetchAt: nil, lastError: nil))
    }

    func testNewerCacheWins() throws {
        try cache.writeData(data(5))
        let s = store()
        XCTAssertEqual(s.activePack.packVersion, 5)
        XCTAssertEqual(s.status.source, .cached)
    }

    func testOlderOrInvalidCacheIgnored() throws {
        try cache.writeData(data(1))
        XCTAssertEqual(store().status.source, .bundled)
        try cache.writeData(Data("not json".utf8))
        XCTAssertEqual(store().status.source, .bundled)
    }

    func testNewerRemoteWinsAndIsCached() async {
        let s = store(fetch: .success(data(7)))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 7)
        XCTAssertEqual(s.status.source, .remote)
        XCTAssertEqual(s.status.packVersion, 7)
        XCTAssertNil(s.status.lastError)
        XCTAssertEqual(s.status.lastFetchAt, Date(timeIntervalSince1970: 1000))
        // A fresh store picks the cached copy up.
        let again = store()
        XCTAssertEqual(again.status.source, .cached)
        XCTAssertEqual(again.activePack.packVersion, 7)
    }

    func testEqualRemoteVersionIsAccepted() async {
        let s = store(fetch: .success(data(2)))
        await s.refresh()
        XCTAssertEqual(s.status.source, .remote)
    }

    func testOlderRemoteIgnored() async {
        let s = store(fetch: .success(data(1)))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 2)
        XCTAssertEqual(s.status.source, .bundled)
        XCTAssertNotNil(s.status.lastError)
        XCTAssertNil(cache.readData())
    }

    func testInvalidRemoteIgnoredAndErrorRecorded() async {
        var bad = pack(9)
        bad.sites[0].homeURL = "http://m.youtube.com/"
        let s = store(fetch: .success(try! JSONEncoder().encode(bad)))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 2)
        XCTAssertEqual(s.status.source, .bundled)
        XCTAssertNotNil(s.status.lastError)
        XCTAssertNil(cache.readData())
    }

    func testFetchFailureLeavesActivePackUnchanged() async throws {
        try cache.writeData(data(5))
        let s = store(fetch: .failure(Boom()))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 5)
        XCTAssertEqual(s.status.source, .cached)
        XCTAssertNotNil(s.status.lastError)
        XCTAssertEqual(s.status.lastFetchAt, Date(timeIntervalSince1970: 1000))
    }

    func testJSONFileStoreRoundTrip() throws {
        let f = JSONFileStore(url: dir.appendingPathComponent("a/b.json"))
        XCTAssertNil(f.load(RulePack.self))
        try f.save(pack(3))
        XCTAssertEqual(f.load(RulePack.self), pack(3))
        f.remove()
        XCTAssertNil(f.readData())
    }
}
