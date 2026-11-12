import XCTest
import WebKit
import QuietFeedCore
@testable import QuietFeed

private final class LoadWaiter: NSObject, WKNavigationDelegate, WKScriptMessageHandler {
    var continuation: CheckedContinuation<Void, Error>?
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        continuation?.resume(); continuation = nil
    }
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        continuation?.resume(throwing: error); continuation = nil
    }
    func userContentController(_ c: WKUserContentController, didReceive m: WKScriptMessage) {}
}

final class InjectionIntegrationTests: XCTestCase {
    private func repoRoot() -> URL {
        URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent()
    }

    @MainActor
    func testYouTubeFixtureHidesShortsShelfButNotVideos() async throws {
        let model = AppModel()
        let site = try XCTUnwrap(model.sites.first { $0.id == "youtube" })
        let runtime = SiteWebViewFactory.runtimeSource()
        XCTAssertFalse(runtime.isEmpty, "runtime.js must be bundled")

        let waiter = LoadWaiter()
        let webView = SiteWebViewFactory.makeWebView(
            site: site, runtimeSource: runtime, messageHandler: waiter, persistent: false)
        webView.navigationDelegate = waiter

        let html = try String(contentsOf: repoRoot().appendingPathComponent("web/fixtures/youtube-home.html"),
                              encoding: .utf8)
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            waiter.continuation = c
            webView.loadHTMLString(html, baseURL: URL(string: site.homeURL))
        }

        let js = """
        JSON.stringify({
          shelf: getComputedStyle(document.querySelector('ytm-reel-shelf-renderer')).display,
          video: getComputedStyle(document.querySelector('#normal-video')).display,
          style: !!document.getElementById('qf-style')
        })
        """
        let result = try await webView.evaluateJavaScript(js) as? String
        let data = try XCTUnwrap(result?.data(using: .utf8))
        let obj = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(obj["style"] as? Bool, true)
        XCTAssertEqual(obj["shelf"] as? String, "none")
        XCTAssertNotEqual(obj["video"] as? String, "none")
    }
}
