import Foundation
import Observation
import QuietFeedCore

/// Decides when the rule pack should be fetched again.
enum FetchSchedule {
    static let interval: TimeInterval = 6 * 60 * 60

    /// True when there was no previous attempt, the last one was more than `interval` ago,
    /// or the clock has moved backwards past the last attempt.
    static func shouldFetch(lastAttempt: Date?, now: Date, interval: TimeInterval = FetchSchedule.interval) -> Bool {
        guard let last = lastAttempt else { return true }
        let elapsed = now.timeIntervalSince(last)
        return elapsed < 0 || elapsed > interval
    }
}

@Observable
final class AppModel {
    private(set) var pack: RulePack?
    private(set) var loadError: String?
    /// Latest health report per site id, from the injected runtime.
    private(set) var healthReports: [String: HealthReport] = [:]
    private(set) var ruleStatus: RuleStatus?
    private(set) var isChecking = false
    var serverURLText: String

    var sites: [SiteRules] { pack?.sites ?? [] }

    struct RuleStatus: Equatable {
        var source: RuleStore.Source
        var packVersion: Int
        var lastChecked: Date?
        var lastError: String?
    }

    @ObservationIgnored private var store: RuleStore?
    @ObservationIgnored private let defaults: UserDefaults
    private static let serverURLKey = "rules.serverURL"
    private static let lastAttemptKey = "rules.lastAttempt"

    init(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        cacheURL: URL? = nil,
        fetcher: RuleFetching = URLSessionRuleFetcher()
    ) {
        self.defaults = defaults
        let savedURL = defaults.string(forKey: Self.serverURLKey)
        self.serverURLText = savedURL ?? RuleStore.defaultServerURL.absoluteString

        guard let url = bundle.url(forResource: "rulepack", withExtension: "json"),
              let data = try? Data(contentsOf: url) else {
            loadError = "The bundled rules are missing."
            return
        }
        switch RulePackValidator.validate(data) {
        case .failure(let error):
            loadError = "The bundled rules are invalid: \(error)"
        case .success(let bundled):
            let cache = JSONFileStore(url: cacheURL ?? Self.defaultCacheURL())
            let store = RuleStore(
                bundled: bundled, cache: cache, fetcher: fetcher,
                serverURL: URL(string: serverURLText) ?? RuleStore.defaultServerURL)
            self.store = store
            syncFromStore()
        }
    }

    // MARK: Health

    func recordHealth(_ report: HealthReport, for siteId: String) {
        healthReports[siteId] = report
    }

    /// Stale when a canary was missing on the site's home path.
    func isStale(_ site: SiteRules) -> Bool {
        guard let report = healthReports[site.id],
              report.path == (URL(string: site.homeURL)?.path ?? "/") else { return false }
        return report.canaries.contains(false)
    }

    // MARK: Rules

    /// Returns false when the text is not an http or https URL.
    @discardableResult
    func setServerURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return false }
        serverURLText = trimmed
        defaults.set(trimmed, forKey: Self.serverURLKey)
        store?.serverURL = url
        return true
    }

    func refreshRules() async {
        guard let store, !isChecking else { return }
        isChecking = true
        defaults.set(Date(), forKey: Self.lastAttemptKey)
        await store.refresh()
        syncFromStore()
        isChecking = false
    }

    /// Called when the app returns to the foreground.
    func refreshRulesIfDue(now: Date = Date()) async {
        let last = defaults.object(forKey: Self.lastAttemptKey) as? Date
        if FetchSchedule.shouldFetch(lastAttempt: last, now: now) {
            await refreshRules()
        }
    }

    private func syncFromStore() {
        guard let store else { return }
        pack = store.activePack
        let s = store.status
        ruleStatus = RuleStatus(source: s.source, packVersion: s.packVersion,
                                lastChecked: s.lastFetchAt, lastError: s.lastError)
    }

    private static func defaultCacheURL() -> URL {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return base.appendingPathComponent("rulepack.cache.json")
    }
}
