import XCTest
import WebKit
import QuietFeedCore
@testable import QuietFeed

private final class Waiter: NSObject, WKNavigationDelegate {
    var continuation: CheckedContinuation<Void, Error>?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(); continuation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error); continuation = nil
    }
}

final class ContentRuleTests: XCTestCase {
    private let ruleJSON = """
    {"trigger":{"url-filter":".*"},"action":{"type":"css-display-none","selector":".qf-test-hide"}}
    """

    @MainActor
    func testCSSDisplayNoneRuleHidesElement() async throws {
        let rule = try JSONDecoder().decode(JSONValue.self, from: Data(ruleJSON.utf8))
        let id = "qf-test-\(UUID().uuidString)"
        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let list = await ContentRuleCompiler.compile(rules: [rule], identifier: id, store: store)
        let compiled = try XCTUnwrap(list, "rule list should compile")
        addTeardownBlock { try? await store.removeContentRuleList(forIdentifier: id) }

        let config = WKWebViewConfiguration()
        config.userContentController.add(compiled)
        let webView = WKWebView(frame: .zero, configuration: config)
        let waiter = Waiter()
        webView.navigationDelegate = waiter
        let html = "<html><body><p id='hide' class='qf-test-hide'>x</p><p id='keep'>y</p></body></html>"
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            waiter.continuation = c
            webView.loadHTMLString(html, baseURL: URL(string: "https://m.youtube.com/"))
        }
        let result = try await webView.evaluateJavaScript(
            "getComputedStyle(document.getElementById('hide')).display + '|' + getComputedStyle(document.getElementById('keep')).display"
        ) as? String
        XCTAssertEqual(result?.split(separator: "|").first.map(String.init), "none")
        XCTAssertNotEqual(result?.split(separator: "|").last.map(String.init), "none")
    }

    @MainActor
    func testEmptyRulesAreSkipped() async throws {
        let site = SiteRules(id: "youtube", name: "Y", homeURL: "https://m.youtube.com/", allowedHosts: ["youtube.com"])
        let list = await ContentRuleCompiler.compile(site: site)
        XCTAssertNil(list)
    }

    @MainActor
    func testInvalidRulesFailQuietly() async throws {
        let bad = JSONValue.object(["trigger": .object([:])])
        let store = try XCTUnwrap(WKContentRuleListStore.default())
        let list = await ContentRuleCompiler.compile(rules: [bad], identifier: "qf-test-bad", store: store)
        XCTAssertNil(list)
    }
}
