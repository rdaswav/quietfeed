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
        default: return UUID(uuidString: "6F1B7A10-00FF-4C0D-9A11-51F0000000FF")!
        }
    }

    static func runtimeSource(bundle: Bundle = .main) -> String {
        guard let url = bundle.url(forResource: "runtime", withExtension: "js"),
              let text = try? String(contentsOf: url, encoding: .utf8) else { return "" }
        return text
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

        let script = WKUserScript(
            source: InjectionBuilder.script(for: site, runtimeSource: runtimeSource),
            injectionTime: .atDocumentStart,
            forMainFrameOnly: true,
            in: .page
        )
        config.userContentController.addUserScript(script)
        config.userContentController.add(WeakScriptMessageHandler(messageHandler), name: "quietfeed")

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
        webView.backgroundColor = UIColor(Theme.bg)
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
