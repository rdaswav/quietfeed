import Foundation
import UIKit
import WebKit
import QuietFeedCore

/// What the injected runtime reports about page health. Built from untrusted page data,
/// so every field is type-checked before use.
struct HealthReport: Equatable {
    var path: String
    var canaries: [Bool]
    var hideCounts: [String: Int]
    /// How many things the script hid on the page, for the quiet notice in the browser.
    var hiddenCount: Int

    init?(body: Any) {
        guard let dict = body as? [String: Any],
              dict["type"] as? String == "health",
              let path = dict["path"] as? String,
              let canaries = dict["canaries"] as? [Any],
              let counts = dict["hideCounts"] as? [String: Any] else { return nil }
        var flags: [Bool] = []
        for c in canaries {
            guard let b = c as? Bool else { return nil }
            flags.append(b)
        }
        var hide: [String: Int] = [:]
        for (k, v) in counts {
            guard let n = v as? Int else { return nil }
            hide[k] = n
        }
        self.path = path
        self.canaries = flags
        self.hideCounts = hide
        self.hiddenCount = dict["hiddenCount"] as? Int ?? 0
    }
}

/// Avoids the retain cycle WKUserContentController creates with its message handlers.
final class WeakScriptMessageHandler: NSObject, WKScriptMessageHandler {
    private weak var target: WKScriptMessageHandler?

    init(_ target: WKScriptMessageHandler) {
        self.target = target
    }

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        target?.userContentController(controller, didReceive: message)
    }
}

/// Maps a URLPolicy decision to what the web view should do.
enum NavigationOutcome: Equatable {
    case allow
    case cancel
    case cancelAndOpenExternally
    case cancelAndLoad(URL)
}

enum NavigationPolicyMapper {
    /// `.allow` plus 2 is the undocumented but long-stable policy value that allows the
    /// navigation while suppressing universal links, so a tapped link never jumps into an
    /// official app. Kept in this one helper on purpose.
    static var allowWithoutUniversalLinks: WKNavigationActionPolicy {
        WKNavigationActionPolicy(rawValue: WKNavigationActionPolicy.allow.rawValue + 2) ?? .allow
    }

    static func outcome(for decision: URLPolicy.Decision) -> NavigationOutcome {
        switch decision {
        case .allow: return .allow
        case .cancel: return .cancel
        case .openExternally: return .cancelAndOpenExternally
        case .redirect(let url): return .cancelAndLoad(url)
        }
    }

    static func actionPolicy(for outcome: NavigationOutcome) -> WKNavigationActionPolicy {
        outcome == .allow ? allowWithoutUniversalLinks : .cancel
    }
}

final class WebCoordinator: NSObject, WKScriptMessageHandler, WKNavigationDelegate, WKUIDelegate {
    let site: SiteRules
    var onHealth: (String, HealthReport) -> Void
    var openExternally: (URL) -> Void = { url in
        Task { @MainActor in ExternalLinkSheet.present(url: url) }
    }

    init(site: SiteRules, onHealth: @escaping (String, HealthReport) -> Void) {
        self.site = site
        self.onHealth = onHealth
    }

    // MARK: Script messages

    func userContentController(_ controller: WKUserContentController, didReceive message: WKScriptMessage) {
        guard message.name == "quietfeed", let report = HealthReport(body: message.body) else { return }
        onHealth(site.id, report)
    }

    // MARK: Navigation policy

    func webView(
        _ webView: WKWebView,
        decidePolicyFor navigationAction: WKNavigationAction,
        decisionHandler: @escaping (WKNavigationActionPolicy) -> Void
    ) {
        guard let url = navigationAction.request.url else {
            decisionHandler(.cancel)
            return
        }
        // Blank frames used by pages internally are harmless and not worth cancelling.
        if url.scheme?.lowercased() == "about" {
            decisionHandler(.allow)
            return
        }
        let isMainFrame = navigationAction.targetFrame?.isMainFrame ?? true
        let outcome = NavigationPolicyMapper.outcome(
            for: URLPolicy.decide(url: url, site: site, isMainFrame: isMainFrame))
        #if DEBUG
        if isMainFrame {
            switch outcome {
            case .allow: DebugEventLog.record(site.id, "main allow \(DebugEventLog.path(url))")
            case .cancel: DebugEventLog.record(site.id, "main cancel \(DebugEventLog.path(url))")
            case .cancelAndOpenExternally: DebugEventLog.record(site.id, "main external \(url.host ?? "?")")
            case .cancelAndLoad(let target):
                DebugEventLog.record(site.id, "main REDIRECT \(DebugEventLog.path(url)) -> \(DebugEventLog.path(target))")
            }
        }
        #endif
        switch outcome {
        case .cancelAndOpenExternally: openExternally(url)
        case .cancelAndLoad(let target): webView.load(URLRequest(url: target))
        case .allow, .cancel: break
        }
        decisionHandler(NavigationPolicyMapper.actionPolicy(for: outcome))
    }

    /// The web process was killed, usually for memory. Without this the page stays blank until the next navigation.
    func webViewWebContentProcessDidTerminate(_ webView: WKWebView) {
        #if DEBUG
        DebugEventLog.record(site.id, "PROCESS TERMINATED, reloading \(DebugEventLog.path(webView.url))")
        #endif
        webView.reload()
    }

    #if DEBUG
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        DebugEventLog.record(site.id, "finished \(DebugEventLog.path(webView.url))")
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        DebugEventLog.record(site.id, "failed \((error as NSError).code)")
    }
    #endif

    // MARK: UI delegate

    /// target="_blank" and window.open load in the same web view.
    func webView(
        _ webView: WKWebView,
        createWebViewWith configuration: WKWebViewConfiguration,
        for navigationAction: WKNavigationAction,
        windowFeatures: WKWindowFeatures
    ) -> WKWebView? {
        if navigationAction.targetFrame == nil {
            webView.load(navigationAction.request)
        }
        return nil
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptAlertPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping () -> Void
    ) {
        presentAlert(message: message, actions: [("OK", .default, { completionHandler() })],
                     fallback: completionHandler)
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptConfirmPanelWithMessage message: String,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (Bool) -> Void
    ) {
        presentAlert(
            message: message,
            actions: [("Cancel", .cancel, { completionHandler(false) }), ("OK", .default, { completionHandler(true) })],
            fallback: { completionHandler(false) })
    }

    func webView(
        _ webView: WKWebView,
        runJavaScriptTextInputPanelWithPrompt prompt: String,
        defaultText: String?,
        initiatedByFrame frame: WKFrameInfo,
        completionHandler: @escaping (String?) -> Void
    ) {
        Task { @MainActor in
            guard let top = ExternalLinkSheet.topViewController() else { completionHandler(nil); return }
            let alert = UIAlertController(title: nil, message: prompt, preferredStyle: .alert)
            alert.addTextField { $0.text = defaultText }
            alert.addAction(UIAlertAction(title: "Cancel", style: .cancel) { _ in completionHandler(nil) })
            alert.addAction(UIAlertAction(title: "OK", style: .default) { _ in
                completionHandler(alert.textFields?.first?.text)
            })
            top.present(alert, animated: true)
        }
    }

    /// Grants camera and microphone only to the site's own origin, so posting photos works.
    func webView(
        _ webView: WKWebView,
        requestMediaCapturePermissionFor origin: WKSecurityOrigin,
        initiatedByFrame frame: WKFrameInfo,
        type: WKMediaCaptureType,
        decisionHandler: @escaping (WKPermissionDecision) -> Void
    ) {
        let host = origin.host.lowercased()
        let own = site.allowedHosts.contains { a in
            let a = a.lowercased()
            return host == a || host.hasSuffix("." + a)
        }
        decisionHandler(own ? .grant : .deny)
    }

    private func presentAlert(
        message: String,
        actions: [(String, UIAlertAction.Style, () -> Void)],
        fallback: @escaping () -> Void
    ) {
        Task { @MainActor in
            guard let top = ExternalLinkSheet.topViewController() else { fallback(); return }
            let alert = UIAlertController(title: nil, message: message, preferredStyle: .alert)
            for (title, style, handler) in actions {
                alert.addAction(UIAlertAction(title: title, style: style) { _ in handler() })
            }
            top.present(alert, animated: true)
        }
    }
}
