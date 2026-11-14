import XCTest
import CryptoKit
@testable import QuietFeedCore

final class RuleStoreTests: XCTestCase {
    private final class CountingFetcher: RuleFetching, @unchecked Sendable {
        var result: Result<Data, Error>
        private(set) var calls = 0
        private(set) var lastURL: URL?
        init(_ result: Result<Data, Error>) { self.result = result }
        func fetch(url: URL) async throws -> Data {
            calls += 1
            lastURL = url
            return try result.get()
        }
    }
    private struct Boom: Error {}

    private var dir: URL!
    private let signingKey = Curve25519.Signing.PrivateKey()
    private let otherKey = Curve25519.Signing.PrivateKey()

    override func setUpWithError() throws {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("rulestore-\(UUID().uuidString)")
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: dir)
    }

    private func pack(_ version: Int, minApp: String? = nil) -> RulePack {
        let site = SiteRules(id: "youtube", name: "YouTube", homeURL: "https://m.youtube.com/",
                             allowedHosts: ["youtube.com"], hideSelectors: ["v\(version)"])
        return RulePack(schemaVersion: 1, packVersion: version, updated: "2026-11-13", minAppVersion: minApp, sites: [site])
    }

    private func data(_ version: Int, minApp: String? = nil) -> Data {
        try! JSONEncoder().encode(pack(version, minApp: minApp))
    }

    /// The signed envelope the official host would serve.
    private func signed(_ version: Int, minApp: String? = nil, with key: Curve25519.Signing.PrivateKey? = nil,
                        keyId: String = "k1") -> Data {
        let payload = data(version, minApp: minApp)
        let sig = try! (key ?? signingKey).signature(for: payload)
        return try! JSONEncoder().encode(
            SignedPackEnvelope(keyId: keyId, payload: payload.base64EncodedString(), signature: sig.base64EncodedString()))
    }

    private var cache: JSONFileStore { JSONFileStore(url: dir.appendingPathComponent("rulepack.cache.json")) }

    private static let testServer = URL(string: "https://rules.example.test/rulepack.json")!
    private static let officialTest = URL(string: "https://official.example.test/v1/rulepack.json")!

    private var verifier: PackVerifier { PackVerifier(publicKeys: ["k1": signingKey.publicKey.rawRepresentation]) }

    private func custom(bundled: Int = 2, fetch: Result<Data, Error> = .failure(Boom()),
                        appVersion: String = "1.0") -> RuleStore {
        RuleStore(bundled: pack(bundled), cache: cache, fetcher: CountingFetcher(fetch),
                  ruleSource: .custom(RuleStoreTests.testServer), appVersion: appVersion,
                  now: { Date(timeIntervalSince1970: 1000) })
    }

    private func official(bundled: Int = 2, fetcher: CountingFetcher? = nil, verifier: PackVerifier? = nil,
                          appVersion: String = "1.0") -> RuleStore {
        RuleStore(bundled: pack(bundled), cache: cache, fetcher: fetcher ?? CountingFetcher(.failure(Boom())),
                  ruleSource: .official, verifier: verifier ?? self.verifier, officialURL: RuleStoreTests.officialTest,
                  appVersion: appVersion, now: { Date(timeIntervalSince1970: 1000) })
    }

    // MARK: Official, signed

    func testOfficialValidSignedPackIsAcceptedAndCachedAsAnEnvelope() async {
        let served = signed(7) // CryptoKit signatures are randomised, so keep the exact bytes that were served
        let f = CountingFetcher(.success(served))
        let s = official(fetcher: f)
        await s.refresh()
        XCTAssertEqual(f.lastURL, RuleStoreTests.officialTest)
        XCTAssertEqual(s.activePack.packVersion, 7)
        XCTAssertEqual(s.status.source, .official)
        XCTAssertNil(s.status.lastError)
        XCTAssertEqual(cache.readData(), served)
        // A fresh store verifies the cached envelope again and uses it.
        let again = official()
        XCTAssertEqual(again.status.source, .cached)
        XCTAssertEqual(again.activePack.packVersion, 7)
    }

    func testOfficialTamperedPackIsRejectedAndThePreviousOneKept() async {
        var envelope = try! JSONDecoder().decode(SignedPackEnvelope.self, from: signed(7))
        var bytes = [UInt8](Data(base64Encoded: envelope.payload)!)
        bytes[bytes.count - 3] ^= 0x01
        envelope = SignedPackEnvelope(keyId: envelope.keyId, payload: Data(bytes).base64EncodedString(), signature: envelope.signature)
        let s = official(fetcher: CountingFetcher(.success(try! JSONEncoder().encode(envelope))))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 2)
        XCTAssertEqual(s.status.source, .bundled)
        XCTAssertNotNil(s.status.lastError)
        XCTAssertNil(cache.readData())
    }

    func testOfficialPackSignedByAnotherKeyIsRejected() async {
        let s = official(fetcher: CountingFetcher(.success(signed(7, with: otherKey))))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 2)
        XCTAssertNotNil(s.status.lastError)
    }

    func testOfficialRejectsAPlainUnsignedPack() async {
        let s = official(fetcher: CountingFetcher(.success(data(9))))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 2)
        XCTAssertEqual(s.status.source, .bundled)
        XCTAssertNotNil(s.status.lastError)
        XCTAssertNil(cache.readData())
    }

    func testOfficialOlderSignedPackIsIgnored() async {
        let s = official(fetcher: CountingFetcher(.success(signed(1))))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 2)
        XCTAssertNotNil(s.status.lastError)
        XCTAssertNil(cache.readData())
    }

    func testOfficialWithNoKeysMakesNoRequestAndRecordsNothing() async {
        let f = CountingFetcher(.success(signed(9)))
        let s = official(fetcher: f, verifier: PackVerifier(publicKeys: [:]))
        await s.refresh()
        XCTAssertEqual(f.calls, 0)
        XCTAssertEqual(s.status, RuleStore.Status(source: .bundled, packVersion: 2, lastFetchAt: nil, lastError: nil))
    }

    func testTheShippedOfficialSourceStaysOffUntilAKeyIsAdded() {
        // T34 adds the real key. Until then the shipped list is empty, so the app never trusts a remote pack.
        // Update this test in T34 to expect exactly one 32 byte key.
        XCTAssertTrue(OfficialRules.publicKeys.isEmpty || OfficialRules.publicKeys.values.allSatisfy { $0.count == 32 })
    }

    func testACachedOfficialEnvelopeSignedByAnotherKeyIsNotTrustedAtLaunch() throws {
        try cache.writeData(signed(5, with: otherKey))
        XCTAssertEqual(official().status.source, .bundled)
    }

    func testAPlainCachedPackIsNotTrustedByTheOfficialSource() throws {
        try cache.writeData(data(5))
        XCTAssertEqual(official().status.source, .bundled)
    }

    func testAnOfficialCacheIsIgnoredByACustomSource() throws {
        try cache.writeData(signed(5))
        XCTAssertEqual(custom().status.source, .bundled)
    }

    // MARK: Minimum app version

    func testAPackNeedingANewerAppIsIgnored() async {
        let official = official(fetcher: CountingFetcher(.success(signed(8, minApp: "2.0"))), appVersion: "1.4")
        await official.refresh()
        XCTAssertEqual(official.activePack.packVersion, 2)
        XCTAssertNotNil(official.status.lastError)
        XCTAssertNil(cache.readData())
        let c = custom(fetch: .success(data(8, minApp: "1.5")), appVersion: "1.4.9")
        await c.refresh()
        XCTAssertEqual(c.activePack.packVersion, 2)
    }

    func testAPackForThisAppOrOlderIsAccepted() async {
        let s = official(fetcher: CountingFetcher(.success(signed(8, minApp: "1.4"))), appVersion: "1.4.0")
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 8)
    }

    func testACachedPackNeedingANewerAppIsNotUsedAtLaunch() throws {
        try cache.writeData(signed(8, minApp: "3.0"))
        XCTAssertEqual(official(appVersion: "1.0").status.source, .bundled)
    }

    // MARK: Custom server (plain, unsigned, as before)

    func testBundledOnly() {
        let s = custom()
        XCTAssertEqual(s.activePack.packVersion, 2)
        XCTAssertEqual(s.status, RuleStore.Status(source: .bundled, packVersion: 2, lastFetchAt: nil, lastError: nil))
    }

    func testNewerCacheWins() throws {
        try cache.writeData(data(5))
        let s = custom()
        XCTAssertEqual(s.activePack.packVersion, 5)
        XCTAssertEqual(s.status.source, .cached)
    }

    func testOlderOrInvalidCacheIgnored() throws {
        try cache.writeData(data(1))
        XCTAssertEqual(custom().status.source, .bundled)
        try cache.writeData(Data("not json".utf8))
        XCTAssertEqual(custom().status.source, .bundled)
    }

    func testNewerCustomPackWinsAndIsCached() async {
        let s = custom(fetch: .success(data(7)))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 7)
        XCTAssertEqual(s.status.source, .custom)
        XCTAssertEqual(s.status.packVersion, 7)
        XCTAssertNil(s.status.lastError)
        XCTAssertEqual(s.status.lastFetchAt, Date(timeIntervalSince1970: 1000))
        let again = custom()
        XCTAssertEqual(again.status.source, .cached)
        XCTAssertEqual(again.activePack.packVersion, 7)
    }

    func testEqualCustomVersionIsAccepted() async {
        let s = custom(fetch: .success(data(2)))
        await s.refresh()
        XCTAssertEqual(s.status.source, .custom)
    }

    func testOlderCustomPackIgnored() async {
        let s = custom(fetch: .success(data(1)))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 2)
        XCTAssertEqual(s.status.source, .bundled)
        XCTAssertNotNil(s.status.lastError)
        XCTAssertNil(cache.readData())
    }

    func testInvalidCustomPackIgnoredAndErrorRecorded() async {
        var bad = pack(9)
        bad.sites[0].homeURL = "http://m.youtube.com/"
        let s = custom(fetch: .success(try! JSONEncoder().encode(bad)))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 2)
        XCTAssertEqual(s.status.source, .bundled)
        XCTAssertNotNil(s.status.lastError)
        XCTAssertNil(cache.readData())
    }

    func testFetchFailureLeavesActivePackUnchanged() async throws {
        try cache.writeData(data(5))
        let s = custom(fetch: .failure(Boom()))
        await s.refresh()
        XCTAssertEqual(s.activePack.packVersion, 5)
        XCTAssertEqual(s.status.source, .cached)
        XCTAssertNotNil(s.status.lastError)
        XCTAssertEqual(s.status.lastFetchAt, Date(timeIntervalSince1970: 1000))
    }

    func testSwitchingSourceChangesWhereItFetchesFrom() async {
        let f = CountingFetcher(.success(data(3)))
        let s = RuleStore(bundled: pack(2), cache: cache, fetcher: f, ruleSource: .custom(RuleStoreTests.testServer),
                          verifier: verifier, officialURL: RuleStoreTests.officialTest)
        await s.refresh()
        XCTAssertEqual(f.lastURL, RuleStoreTests.testServer)
        s.ruleSource = .official
        f.result = .success(signed(4))
        await s.refresh()
        XCTAssertEqual(f.lastURL, RuleStoreTests.officialTest)
        XCTAssertEqual(s.status.source, .official)
        XCTAssertEqual(s.activePack.packVersion, 4)
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
