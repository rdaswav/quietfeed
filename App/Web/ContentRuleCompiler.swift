import Foundation
import OSLog
import WebKit
import QuietFeedCore

enum ContentRuleCompiler {
    private static let log = Logger(subsystem: "dev.quietfeed.app", category: "ContentRules")

    static func identifier(for siteId: String) -> String { "qf-\(siteId)" }

    /// Compiles a site's raw `contentRules`. Returns nil when there are none, or when
    /// compilation fails (the failure is logged and ignored so the site still works).
    @MainActor
    static func compile(
        site: SiteRules,
        store: WKContentRuleListStore? = WKContentRuleListStore.default()
    ) async -> WKContentRuleList? {
        guard !site.contentRules.isEmpty, let store else { return nil }
        return await compile(rules: site.contentRules, identifier: identifier(for: site.id), store: store)
    }

    @MainActor
    static func compile(
        rules: [JSONValue],
        identifier: String,
        store: WKContentRuleListStore
    ) async -> WKContentRuleList? {
        guard !rules.isEmpty else { return nil }
        do {
            let data = try JSONEncoder().encode(rules)
            let json = String(decoding: data, as: UTF8.self)
            return try await store.compileContentRuleList(forIdentifier: identifier, encodedContentRuleList: json)
        } catch {
            log.error("Content rule compile failed for \(identifier, privacy: .public): \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
