import XCTest
@testable import QuietFeed

final class ReportingTests: XCTestCase {
    private let input = BrokenRuleReport.Input(
        siteId: "instagram", siteName: "Instagram", appVersion: "1.0", packVersion: 3,
        rulesSource: "official", health: "all found")

    private func query(_ url: URL, _ name: String) -> String? {
        URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.first { $0.name == name }?.value
    }

    func testTheAddressIsAGitHubNewIssueFormUnderTheRepo() throws {
        let url = try XCTUnwrap(BrokenRuleReport.url(input))
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/rdaswav/quietfeed/issues/new")
        XCTAssertEqual(query(url, "title"), "Broken rules: Instagram")
    }

    func testTheBodyCarriesOnlyTheVersionsSourceAndHealth() throws {
        let body = try XCTUnwrap(query(try XCTUnwrap(BrokenRuleReport.url(input)), "body"))
        for expected in ["Instagram (instagram)", "App version: 1.0", "Rules version: 3", "Rules from: official", "Page check: all found"] {
            XCTAssertTrue(body.contains(expected), expected)
        }
        // The input has no field that could hold a page address, page text or a name, so none can appear.
        XCTAssertFalse(body.contains("http"))
        XCTAssertFalse(body.contains("?"))
        XCTAssertTrue(body.contains("do not include passwords"))
    }

    func testItIsShortAndFullyPercentEncoded() throws {
        let url = try XCTUnwrap(BrokenRuleReport.url(input))
        XCTAssertLessThan(url.absoluteString.count, 2000)
        XCTAssertFalse(url.absoluteString.contains(" "))
        XCTAssertFalse(url.absoluteString.contains("\n"))
    }

    func testUnusualSiteNamesCannotBreakOutOfTheirQueryValue() throws {
        var odd = input
        odd.siteName = "A&body=evil #x"
        let url = try XCTUnwrap(BrokenRuleReport.url(odd))
        XCTAssertEqual(query(url, "title"), "Broken rules: A&body=evil #x")
        let bodyItems = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems?.filter { $0.name == "body" }
        XCTAssertEqual(bodyItems?.count, 1)
    }

    func testTheModelReportsOnlyWhatItKnows() throws {
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("rp-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: dir) }
        let model = AppModel(
            defaults: UserDefaults(suiteName: "rp-\(UUID().uuidString)")!,
            cacheURL: dir.appendingPathComponent("c.json"),
            usageURL: dir.appendingPathComponent("u.json"),
            limitsURL: dir.appendingPathComponent("l.json"),
            shield: FakeShieldController())
        let site = try XCTUnwrap(model.sites.first { $0.id == "instagram" })
        let url = try XCTUnwrap(model.brokenRuleReportURL(for: site))
        let body = try XCTUnwrap(query(url, "body"))
        XCTAssertTrue(body.contains("Rules from: built in"))
        XCTAssertTrue(body.contains("Page check: not checked yet"))
        XCTAssertFalse(body.contains("192."))
    }
}
