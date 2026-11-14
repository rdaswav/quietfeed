import XCTest
@testable import QuietFeedCore

final class RulePackTests: XCTestCase {
    private func packURL() -> URL {
        // .../Packages/QuietFeedCore/Tests/QuietFeedCoreTests/RulePackTests.swift -> repo root
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("rules/rulepack.json")
    }

    func testBundledPackDecodes() throws {
        let data = try Data(contentsOf: packURL())
        let pack = try JSONDecoder().decode(RulePack.self, from: data)
        XCTAssertEqual(pack.schemaVersion, 1)
        XCTAssertGreaterThanOrEqual(pack.packVersion, 1)  // rises whenever the rules are tuned
        XCTAssertEqual(pack.sites.count, 4)
        XCTAssertEqual(pack.sites.map(\.id), ["instagram", "youtube", "facebook", "tiktok"])
        let yt = try XCTUnwrap(pack.sites.first { $0.id == "youtube" })
        XCTAssertEqual(yt.pathRules.first?.action, .redirect)
        XCTAssertEqual(yt.pathRules.first?.to, "/watch?v=$1")
    }

    func testRoundTrip() throws {
        let data = try Data(contentsOf: packURL())
        let pack = try JSONDecoder().decode(RulePack.self, from: data)
        let encoded = try JSONEncoder().encode(pack)
        let again = try JSONDecoder().decode(RulePack.self, from: encoded)
        XCTAssertEqual(pack, again)
    }

    func testContentRulesKeptAsRawJSON() throws {
        let json = """
        {"schemaVersion":1,"packVersion":2,"updated":"2026-01-01","sites":[{"id":"x","name":"X",
        "homeURL":"https://x.com/","allowedHosts":["x.com"],"pathRules":[],"hideSelectors":[],
        "hideByText":[],"contentRules":[{"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".a"}}],
        "canaries":[]}]}
        """.data(using: .utf8)!
        let pack = try JSONDecoder().decode(RulePack.self, from: json)
        XCTAssertEqual(pack.sites[0].contentRules.count, 1)
        guard case .object(let o) = pack.sites[0].contentRules[0] else { return XCTFail("not object") }
        XCTAssertNotNil(o["trigger"])
        let again = try JSONDecoder().decode(RulePack.self, from: JSONEncoder().encode(pack))
        XCTAssertEqual(pack, again)
    }
}
