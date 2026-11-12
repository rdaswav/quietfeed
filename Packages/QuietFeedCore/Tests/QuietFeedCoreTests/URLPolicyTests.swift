import XCTest
@testable import QuietFeedCore

final class URLPolicyTests: XCTestCase {
    private var packSites: [String: SiteRules] = [:]

    override func setUpWithError() throws {
        let url = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().appendingPathComponent("rules/rulepack.json")
        let pack = try JSONDecoder().decode(RulePack.self, from: Data(contentsOf: url))
        packSites = Dictionary(uniqueKeysWithValues: pack.sites.map { ($0.id, $0) })
    }

    private struct Row {
        let site: String
        let url: String
        let main: Bool
        let expected: URLPolicy.Decision
        var line: UInt = #line
    }

    private func u(_ s: String) -> URL { URL(string: s)! }

    func testTable() {
        let rows: [Row] = [
            Row(site: "instagram", url: "instagram://media?id=1", main: true, expected: .cancel),
            Row(site: "facebook", url: "fb://profile", main: true, expected: .cancel),
            Row(site: "youtube", url: "intent://x#Intent;end", main: true, expected: .cancel),
            Row(site: "youtube", url: "itms-apps://apps.apple.com/app/1", main: true, expected: .cancel),
            Row(site: "youtube", url: "mailto:a@b.com", main: false, expected: .cancel),
            Row(site: "youtube", url: "https://example.com/x", main: false, expected: .allow),
            Row(site: "youtube", url: "https://m.youtube.com/watch?v=abc", main: true, expected: .allow),
            Row(site: "youtube", url: "https://m.youtube.com/", main: true, expected: .allow),
            Row(site: "youtube", url: "https://example.com/", main: true, expected: .openExternally),
            Row(site: "youtube", url: "https://evil-youtube.com/", main: true, expected: .openExternally),
            Row(site: "youtube", url: "https://youtube.com.evil.com/", main: true, expected: .openExternally),
            Row(site: "youtube", url: "https://accounts.google.com/signin", main: true, expected: .allow),
            Row(site: "youtube", url: "https://YOUTUBE.com/watch", main: true, expected: .allow),
            Row(site: "youtube", url: "https://m.youtube.com/shorts/abc_DEF-1",
                main: true, expected: .redirect(URL(string: "https://m.youtube.com/watch?v=abc_DEF-1")!)),
            Row(site: "youtube", url: "https://m.youtube.com/shorts/",
                main: true, expected: .redirect(URL(string: "https://m.youtube.com/")!)),
            Row(site: "youtube", url: "https://m.youtube.com/shorts",
                main: true, expected: .redirect(URL(string: "https://m.youtube.com/")!)),
            Row(site: "youtube", url: "https://m.youtube.com/shorts/abc", main: false, expected: .allow),
            Row(site: "instagram", url: "https://www.instagram.com/reels/",
                main: true, expected: .redirect(URL(string: "https://www.instagram.com/")!)),
            Row(site: "instagram", url: "https://www.instagram.com/reels",
                main: true, expected: .redirect(URL(string: "https://www.instagram.com/")!)),
            Row(site: "instagram", url: "https://www.instagram.com/explore/tags/x/",
                main: true, expected: .redirect(URL(string: "https://www.instagram.com/")!)),
            Row(site: "instagram", url: "https://www.instagram.com/reel/abc/", main: true, expected: .allow),
            Row(site: "instagram", url: "https://www.instagram.com/p/abc/", main: true, expected: .allow),
            Row(site: "instagram", url: "https://www.instagram.com/reelsfoo/", main: true, expected: .allow),
            Row(site: "instagram", url: "https://l.instagram.com/?u=x", main: true, expected: .allow),
            Row(site: "facebook", url: "https://m.facebook.com/reel/123",
                main: true, expected: .redirect(URL(string: "https://m.facebook.com/")!)),
            Row(site: "facebook", url: "https://m.facebook.com/watch/?v=1",
                main: true, expected: .redirect(URL(string: "https://m.facebook.com/")!)),
            Row(site: "facebook", url: "https://m.facebook.com/friends", main: true, expected: .allow),
        ]
        XCTAssertGreaterThanOrEqual(rows.count, 20)
        for r in rows {
            let got = URLPolicy.decide(url: u(r.url), site: packSites[r.site]!, isMainFrame: r.main)
            XCTAssertEqual(got, r.expected, r.url, line: r.line)
        }
    }

    func testBlockActionCancels() {
        let site = SiteRules(id: "youtube", name: "Y", homeURL: "https://a.com/", allowedHosts: ["a.com"],
                             pathRules: [PathRule(pattern: "^/no", action: .block)])
        XCTAssertEqual(URLPolicy.decide(url: u("https://a.com/nope"), site: site, isMainFrame: true), .cancel)
    }

    func testRedirectSubstitutesMultipleGroupsAndKeepsPort() {
        let site = SiteRules(id: "youtube", name: "Y", homeURL: "https://a.com/", allowedHosts: ["a.com"],
                             pathRules: [PathRule(pattern: "^/x/(\\w+)/(\\w+)", action: .redirect, to: "/y/$2/$1")])
        XCTAssertEqual(URLPolicy.decide(url: u("https://a.com:8443/x/one/two"), site: site, isMainFrame: true),
                       .redirect(u("https://a.com:8443/y/two/one")))
    }
}
