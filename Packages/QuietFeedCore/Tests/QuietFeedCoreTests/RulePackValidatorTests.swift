import XCTest
@testable import QuietFeedCore

final class RulePackValidatorTests: XCTestCase {
    private func goodSite(id: String = "youtube") -> SiteRules {
        SiteRules(id: id, name: "N", homeURL: "https://m.youtube.com/",
                  allowedHosts: ["youtube.com"],
                  pathRules: [PathRule(pattern: "^/shorts/([A-Za-z0-9_-]+)", action: .redirect, to: "/watch?v=$1")],
                  hideSelectors: ["ytm-reel-shelf-renderer"],
                  hideByText: [TextRule(text: "Shorts", within: "a", closest: "a")],
                  canaries: ["body"])
    }

    private func pack(_ mutate: (inout SiteRules) -> Void = { _ in }) -> RulePack {
        var s = goodSite()
        mutate(&s)
        return RulePack(schemaVersion: 1, packVersion: 1, updated: "2026-11-13", sites: [s])
    }

    private func run(_ p: RulePack) -> ValidationError? {
        let data = try! JSONEncoder().encode(p)
        if case .failure(let e) = RulePackValidator.validate(data) { return e }
        return nil
    }

    func testBundledPackPasses() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("rules/rulepack.json")
        let result = RulePackValidator.validate(try Data(contentsOf: url))
        guard case .success(let p) = result else { return XCTFail("\(result)") }
        XCTAssertEqual(p.sites.count, 3)
    }

    func testGoodPackPasses() { XCTAssertNil(run(pack())) }

    func testMalformedJSON() {
        guard case .failure(.malformed) = RulePackValidator.validate(Data("{".utf8)) else { return XCTFail() }
    }

    func testTooLarge() {
        let big = Data(repeating: 0x20, count: RulePackValidator.maxBytes)
        XCTAssertEqual(RulePackValidator.validate(big), .failure(.tooLarge(bytes: big.count)))
    }

    func testUnknownSchemaVersion() {
        var p = pack(); p.schemaVersion = 2
        XCTAssertEqual(run(p), .unknownSchemaVersion(2))
    }

    func testTooManySites() {
        let p = RulePack(schemaVersion: 1, packVersion: 1, updated: "x", sites: Array(repeating: goodSite(), count: 11))
        XCTAssertEqual(run(p), .tooManySites(11))
    }

    func testUnknownSiteId() {
        let p = RulePack(schemaVersion: 1, packVersion: 1, updated: "x", sites: [goodSite(id: "tiktok")])
        XCTAssertEqual(run(p), .unknownSiteId("tiktok"))
    }

    func testListTooLong() {
        let e = run(pack { $0.hideSelectors = Array(repeating: "a", count: 201) })
        XCTAssertEqual(e, .listTooLong(site: "youtube", list: "hideSelectors", count: 201))
    }

    func testInvalidRegex() {
        let e = run(pack { $0.pathRules = [PathRule(pattern: "([", action: .block)] })
        XCTAssertEqual(e, .invalidRegex(site: "youtube", pattern: "(["))
    }

    func testRedirectTargetMustStartWithSlash() {
        let e = run(pack { $0.pathRules = [PathRule(pattern: "^/a", action: .redirect, to: "https://evil.com")] })
        XCTAssertEqual(e, .redirectTarget(site: "youtube", to: "https://evil.com"))
    }

    func testRedirectWithoutTarget() {
        let e = run(pack { $0.pathRules = [PathRule(pattern: "^/a", action: .redirect)] })
        XCTAssertEqual(e, .redirectTarget(site: "youtube", to: nil))
    }

    func testEmptySelector() {
        XCTAssertEqual(run(pack { $0.hideSelectors = ["  "] }), .invalidSelector(site: "youtube", selector: "  "))
    }

    func testLongSelector() {
        let long = String(repeating: "a", count: 300)
        XCTAssertEqual(run(pack { $0.hideSelectors = [long] }), .invalidSelector(site: "youtube", selector: long))
    }

    func testForbiddenSelectorCharacters() {
        for ch in ["{", "}", "<", ";"] {
            let sel = "a\(ch)b"
            XCTAssertEqual(run(pack { $0.hideSelectors = [sel] }), .invalidSelector(site: "youtube", selector: sel), ch)
        }
    }

    /// Relaxed on 2026-11-14: ">" is the child combinator and some sites (Facebook) can only be targeted with it.
    func testChildCombinatorIsAllowedButTagBreakoutIsNot() {
        XCTAssertNil(run(pack { $0.hideSelectors = ["div[data-type=\"x\"] > div"] }))
        let breakout = "a > b</style><script>"
        XCTAssertEqual(run(pack { $0.hideSelectors = [breakout] }), .invalidSelector(site: "youtube", selector: breakout))
        let block = "a > b } c { d"
        XCTAssertEqual(run(pack { $0.hideSelectors = [block] }), .invalidSelector(site: "youtube", selector: block))
    }

    func testBadCanaryAndTextRuleSelectors() {
        XCTAssertNotNil(run(pack { $0.canaries = ["a;b"] }))
        XCTAssertNotNil(run(pack { $0.hideByText = [TextRule(text: "x", closest: "a{")] }))
    }

    func testHomeURLMustBeHTTPS() {
        let e = run(pack { $0.homeURL = "http://m.youtube.com/" })
        XCTAssertEqual(e, .homeURLNotHTTPS(site: "youtube", url: "http://m.youtube.com/"))
    }

    func testHomeHostMustBeAllowed() {
        let e = run(pack { $0.allowedHosts = ["example.com"] })
        XCTAssertEqual(e, .homeHostNotAllowed(site: "youtube", host: "m.youtube.com"))
    }

    func testLookalikeHostNotAllowed() {
        let e = run(pack { $0.allowedHosts = ["tube.com"] })
        XCTAssertEqual(e, .homeHostNotAllowed(site: "youtube", host: "m.youtube.com"))
    }
}
