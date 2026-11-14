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

/// Keeps each site's web view alive after you leave it, so coming back is instant rather than a fresh load.
/// Costs some memory, so it is emptied on a memory warning, and a view left for a while reloads when it returns.
@MainActor
final class WebViewCache {
    static let shared = WebViewCache()
    /// Longer than this away and the feed is stale, so it reloads on return.
    static let staleAfter: TimeInterval = 5 * 60

    private struct Entry {
        let webView: WKWebView
        let coordinator: WebCoordinator
        var leftAt: Date?
    }
    private var entries: [String: Entry] = [:]

    private init() {
        NotificationCenter.default.addObserver(
            forName: UIApplication.didReceiveMemoryWarningNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor in self?.entries.removeAll() }
        }
    }

    func coordinator(for siteId: String) -> WebCoordinator? { entries[siteId]?.coordinator }

    /// A kept web view, reloaded first if it has been away too long. `nil` when there is none.
    func reuse(_ siteId: String) -> WKWebView? {
        guard var entry = entries[siteId] else { return nil }
        if let left = entry.leftAt, Date().timeIntervalSince(left) > Self.staleAfter {
            entry.webView.reload()
        }
        entry.leftAt = nil
        entries[siteId] = entry
        return entry.webView
    }

    /// Makes a web view for a site, stores it, and starts loading the home page.
    func build(site: SiteRules, runtimeSource: String, coordinator: WebCoordinator, warmed: Bool = false) -> WKWebView {
        let webView = SiteWebViewFactory.makeWebView(
            site: site, runtimeSource: runtimeSource, messageHandler: coordinator)
        webView.navigationDelegate = coordinator
        webView.uiDelegate = coordinator
        // The web view follows the system light or dark setting (never overridden), and everything around and
        // behind the page uses the app background so overscroll and loading show no stray colour.
        webView.overrideUserInterfaceStyle = .unspecified
        webView.backgroundColor = UIColor(Theme.bg)
        webView.scrollView.backgroundColor = UIColor(Theme.bg)
        webView.underPageBackgroundColor = UIColor(Theme.bg)
        webView.isOpaque = false
        entries[site.id] = Entry(webView: webView, coordinator: coordinator, leftAt: warmed ? Date() : nil)
        let homeURL = URL(string: site.homeURL)
        Task { @MainActor in
            // Content rules must be attached before the first load.
            if let list = await ContentRuleCompiler.compile(site: site) {
                webView.configuration.userContentController.add(list)
            }
            if let homeURL { webView.load(URLRequest(url: homeURL)) }
        }
        return webView
    }

    /// Loads each site's home page in the background, one at a time, so the first open is already
    /// mostly loaded. Skips a site that is already kept or whose time for today is used up.
    func warm(_ sites: [SiteRules], skip: (SiteRules) -> Bool) async {
        let source = SiteWebViewFactory.runtimeSource()
        for site in sites where entries[site.id] == nil && !skip(site) {
            let coordinator = WebCoordinator(site: site, onHealth: { _, _ in })
            _ = build(site: site, runtimeSource: source, coordinator: coordinator, warmed: true)
            #if DEBUG
            DebugEventLog.record(site.id, "warm start")
            #endif
            try? await Task.sleep(for: .seconds(2))
        }
    }

    /// Drops every kept web view, such as when background loading is switched off.
    func clear() { entries.removeAll() }

    func markLeft(_ siteId: String) { entries[siteId]?.leftAt = Date() }
}

struct SiteWebView: UIViewRepresentable {
    let site: SiteRules
    let runtimeSource: String
    let controller: BrowserController?
    let onHealth: (String, HealthReport) -> Void

    func makeCoordinator() -> WebCoordinator {
        WebViewCache.shared.coordinator(for: site.id) ?? WebCoordinator(site: site, onHealth: onHealth)
    }

    func makeUIView(context: Context) -> WKWebView {
        if let kept = WebViewCache.shared.reuse(site.id) {
            context.coordinator.onHealth = onHealth
            controller?.webView = kept
            #if DEBUG
            DebugEventLog.record(site.id, "reuse kept web view")
            #endif
            return kept
        }
        let webView = WebViewCache.shared.build(
            site: site, runtimeSource: runtimeSource, coordinator: context.coordinator)
        controller?.webView = webView
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {
        context.coordinator.onHealth = onHealth
    }
}
