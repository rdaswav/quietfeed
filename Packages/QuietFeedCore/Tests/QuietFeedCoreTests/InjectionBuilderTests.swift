import XCTest
@testable import QuietFeedCore

final class InjectionBuilderTests: XCTestCase {
    private let prefix = "window.__QF_CONFIG__ = "

    private func site(selectors: [String] = ["a.b"], text: [TextRule] = []) -> SiteRules {
        SiteRules(id: "youtube", name: "Y", homeURL: "https://a.com/", allowedHosts: ["a.com"],
                  pathRules: [PathRule(pattern: "^/shorts/([A-Za-z0-9_-]+)", action: .redirect, to: "/watch?v=$1")],
                  hideSelectors: selectors, hideByText: text, canaries: ["nav"])
    }

    /// Splits the output into the JSON object and the remainder after ";\n".
    private func parse(_ out: String) throws -> ([String: Any], String) {
        XCTAssertTrue(out.hasPrefix(prefix))
        let body = String(out.dropFirst(prefix.count))
        let marker = body.range(of: ";\n")!
        let jsonText = String(body[..<marker.lowerBound])
        let rest = String(body[marker.upperBound...])
        let obj = try JSONSerialization.jsonObject(with: Data(jsonText.utf8)) as! [String: Any]
        return (obj, rest)
    }

    func testConfigRoundTripsAndRuntimeFollows() throws {
        let s = site(text: [TextRule(text: "Shorts", within: "span", closest: "article")])
        let (obj, rest) = try parse(InjectionBuilder.script(for: s, runtimeSource: "/*runtime*/"))
        XCTAssertEqual(rest, "/*runtime*/")
        XCTAssertEqual(Set(obj.keys), ["siteId", "pathRules", "hideSelectors", "hideByText", "canaries"])
        XCTAssertEqual(obj["siteId"] as? String, "youtube")
        XCTAssertEqual(obj["hideSelectors"] as? [String], ["a.b"])
        XCTAssertEqual(obj["canaries"] as? [String], ["nav"])
        let pr = (obj["pathRules"] as! [[String: Any]])[0]
        XCTAssertEqual(pr["pattern"] as? String, "^/shorts/([A-Za-z0-9_-]+)")
        XCTAssertEqual(pr["action"] as? String, "redirect")
        XCTAssertEqual(pr["to"] as? String, "/watch?v=$1")
        let tr = (obj["hideByText"] as! [[String: Any]])[0]
        XCTAssertEqual(tr["text"] as? String, "Shorts")
        XCTAssertEqual(tr["within"] as? String, "span")
        XCTAssertEqual(tr["closest"] as? String, "article")
    }

    func testQuotesAndBackslashesSurvive() throws {
        let sel = #"a[href="/x\y"], b[title='q']"#
        let (obj, _) = try parse(InjectionBuilder.script(for: site(selectors: [sel]), runtimeSource: ""))
        XCTAssertEqual(obj["hideSelectors"] as? [String], [sel])
    }

    func testLineSeparatorsAreEscaped() throws {
        let sel = "a[title=\"x\u{2028}y\u{2029}z\"]"
        let out = InjectionBuilder.script(for: site(selectors: [sel]), runtimeSource: "")
        XCTAssertFalse(out.contains("\u{2028}"))
        XCTAssertFalse(out.contains("\u{2029}"))
        XCTAssertTrue(out.contains("\\u2028"))
        XCTAssertTrue(out.contains("\\u2029"))
        let (obj, _) = try parse(out)
        XCTAssertEqual(obj["hideSelectors"] as? [String], [sel])
    }
}
