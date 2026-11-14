import SwiftUI
import WebKit
import QuietFeedCore

enum SiteWebViewFactory {
    /// Current iPhone Safari string. The default WKWebView string lacks the Version/x Safari
    /// suffix and Google sign-in may refuse it.
    static let userAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 18_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/18.0 Mobile/15E148 Safari/604.1"

    /// Fixed identifiers so each site keeps its own cookies and logins across launches.
    static func dataStoreID(for siteId: String) -> UUID {
        switch siteId {
        case "instagram": return UUID(uuidString: "6F1B7A10-0001-4C0D-9A11-51F000000001")!
        case "youtube": return UUID(uuidString: "6F1B7A10-0002-4C0D-9A11-51F000000002")!
        case "facebook": return UUID(uuidString: "6F1B7A10-0003-4C0D-9A11-51F000000003")!
        case "tiktok": return UUID(uuidString: "6F1B7A10-0004-4C0D-9A11-51F000000004")!
        default: return UUID(uuidString: "6F1B7A10-00FF-4C0D-9A11-51F0000000FF")!
        }
    }

    static func runtimeSource(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: "runtime", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
    }

    /// Debug builds only: `-qfDisable text,history` turns those parts of the injected script off
    /// (style, history, text, health) so a misbehaving page can be bisected on a device.
    private static var debugPrefix: String {
        #if DEBUG
        var prefix = ""
        if let list = UserDefaults.standard.string(forKey: "qfDisable") {
            let names = list.split(separator: ",").map { "\"\($0.filter { $0.isLetter })\"" }
            prefix += "window.__QF_DISABLE__ = [\(names.joined(separator: ","))];\n"
        }
        if let mode = UserDefaults.standard.string(forKey: "qfHideMode") {
            prefix += "window.__QF_HIDE_MODE__ = \"\(mode.filter { $0.isLetter })\";\n"
        }
        return prefix
        #endif
        return ""
    }

    static func userScript(site: SiteRules, runtimeSource: String) -> WKUserScript {
        WKUserScript(
            source: debugPrefix + InjectionBuilder.script(for: site, runtimeSource: runtimeSource),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
    }

    @MainActor
    static func makeWebView(
        site: SiteRules,
        runtimeSource: String,
        messageHandler: WKScriptMessageHandler,
        persistent: Bool = true
    ) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.websiteDataStore = persistent
            ? WKWebsiteDataStore(forIdentifier: dataStoreID(for: site.id))
            : .nonPersistent()
        config.allowsInlineMediaPlayback = true
        config.allowsPictureInPictureMediaPlayback = true

        config.userContentController.addUserScript(userScript(site: site, runtimeSource: runtimeSource))
        config.userContentController.add(WeakScriptMessageHandler(messageHandler), name: "quietfeed")
        if let nav = SiteNav.forSite(site.id) {
            config.userContentController.addUserScript(WKUserScript(
                source: nav.hideScript, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: .page))
        }

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.customUserAgent = userAgent
        webView.allowsBackForwardNavigationGestures = true
        #if DEBUG
        webView.isInspectable = true
        #endif
        return webView
    }
}

struct SiteWebView: UIViewRepresentable {
    let site: SiteRules
    let runtimeSource: String
    let controller: BrowserController?
    let onHealth: (String, HealthReport) -> Void

    func makeCoordinator() -> WebCoordinator {
        WebCoordinator(site: site, onHealth: onHealth)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = SiteWebViewFactory.makeWebView(
            site: site, runtimeSource: runtimeSource, messageHandler: context.coordinator)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator
        // The web view follows the system light or dark setting (never overridden), and everything around and
        // behind the page uses the app background so overscroll and loading show no stray colour.
        webView.overrideUserInterfaceStyle = .unspecified
        webView.backgroundColor = UIColor(Theme.bg)
        webView.scrollView.backgroundColor = UIColor(Theme.bg)
        webView.underPageBackgroundColor = UIColor(Theme.bg)
        webView.isOpaque = false
        controller?.webView = webView
        let homeURL = URL(string: site.homeURL)
        let site = site
        Task { @MainActor in
            // Content rules must be attached before the first load.
            if let list = await ContentRuleCompiler.compile(site: site) {
                webView.configuration.userContentController.add(list)
            }
            if let homeURL { webView.load(URLRequest(url: homeURL)) }
        }
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onHealth = onHealth
    }
}
