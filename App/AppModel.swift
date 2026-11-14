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
    /// Limit and friction settings, persisted to limits.json.
    private(set) var limits = LimitSettings()
    /// Bumped whenever usage changes so views that read budget state refresh.
    private(set) var usageVersion = 0
    /// Bumped whenever the shield state changes so views that read it refresh.
    private(set) var shieldVersion = 0
    /// Whether the user wants the official apps shielded. Needs Screen Time access and a chosen set of apps.
    private(set) var shieldEnabled: Bool
    /// Whether Home loads each site in the background so the first open is quick. On by default.
    private(set) var preloadFeeds: Bool
    /// True until the first-run pages have been finished or skipped.
    private(set) var showOnboarding: Bool

    var sites: [SiteRules] { pack?.sites ?? [] }

    struct RuleStatus: Equatable {
        var source: RuleStore.Source
        var packVersion: Int
        var lastChecked: Date?
        var lastError: String?
    }

    @ObservationIgnored private var store: RuleStore?
    @ObservationIgnored let ledger: UsageLedger
    @ObservationIgnored let clock: Clock
    @ObservationIgnored private let limitsStore: JSONFileStore
    @ObservationIgnored private var ticksSinceFlush = 0
    @ObservationIgnored private let defaults: UserDefaults
    @ObservationIgnored let shield: ShieldController
    private static let shieldEnabledKey = "shield.enabled"
    private static let preloadFeedsKey = "preload.feeds"
    private static let onboardingKey = "onboarding.done"
    private static let serverURLKey = "rules.serverURL"
    private static let lastAttemptKey = "rules.lastAttempt"

    init(
        bundle: Bundle = .main,
        defaults: UserDefaults = .standard,
        cacheURL: URL? = nil,
        usageURL: URL? = nil,
        limitsURL: URL? = nil,
        clock: Clock = .system,
        fetcher: RuleFetching = URLSessionRuleFetcher(),
        shield: ShieldController? = nil
    ) {
        self.defaults = defaults
        self.shield = shield ?? Self.makeShield()
        self.shieldEnabled = defaults.bool(forKey: Self.shieldEnabledKey)
        self.preloadFeeds = defaults.object(forKey: Self.preloadFeedsKey) as? Bool ?? true
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-qfResetOnboarding") {
            defaults.removeObject(forKey: Self.onboardingKey)
        }
        #endif
        self.showOnboarding = !defaults.bool(forKey: Self.onboardingKey)
        self.limitsStore = JSONFileStore(url: limitsURL ?? Self.supportURL("limits.json"))
        self.limits = limitsStore.load(LimitSettings.self) ?? LimitSettings()
        self.clock = clock
        self.ledger = UsageLedger(store: JSONFileStore(url: usageURL ?? Self.supportURL("usage.json")), clock: clock)
        let savedURL = defaults.string(forKey: Self.serverURLKey)
        self.serverURLText = savedURL ?? ""

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
            let saved = URL(string: serverURLText)
            let store = RuleStore(
                bundled: bundled, cache: cache, fetcher: fetcher,
                ruleSource: saved.map(RuleSource.custom) ?? .official,
                appVersion: Self.appVersion(bundle))
            self.store = store
            syncFromStore()
        }
    }

    // MARK: Health

    @MainActor func setPreloadFeeds(_ on: Bool) {
        preloadFeeds = on
        defaults.set(on, forKey: Self.preloadFeedsKey)
        if !on { WebViewCache.shared.clear() }
    }

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

    /// Returns false when the text is not an http or https URL. Empty text clears the server.
    @discardableResult
    func setServerURL(_ text: String) -> Bool {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty {
            serverURLText = ""
            defaults.removeObject(forKey: Self.serverURLKey)
            store?.ruleSource = .official
            return true
        }
        guard let url = URL(string: trimmed), let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https", url.host != nil else { return false }
        serverURLText = trimmed
        defaults.set(trimmed, forKey: Self.serverURLKey)
        store?.ruleSource = .custom(url)
        return true
    }

    /// True when the user has chosen their own rules server. A device that already had a saved address
    /// (before the official source existed) is in this state, so nothing changes for it.
    var usesCustomRules: Bool {
        guard let url = URL(string: serverURLText), url.host != nil else { return false }
        return !serverURLText.isEmpty
    }

    /// False while the build has no public key for the official source, so official updates are not on yet.
    var officialRulesAreOn: Bool { !OfficialRules.publicKeys.isEmpty }

    /// Switches back to the official source and forgets the custom address.
    func useOfficialRules() {
        setServerURL("")
    }

    /// The prefilled issue address for a site. Only versions, the rules source and the page check result go in it.
    func brokenRuleReportURL(for site: SiteRules) -> URL? {
        let source: String
        switch ruleStatus?.source {
        case .official: source = "official"
        case .custom: source = "custom server"
        case .cached: source = usesCustomRules ? "custom server (saved copy)" : "official (saved copy)"
        case .bundled, .none: source = "built in"
        }
        let health: String
        if let report = healthReports[site.id] {
            health = report.canaries.contains(false) ? "something missing" : "all found"
        } else {
            health = "not checked yet"
        }
        return BrokenRuleReport.url(.init(
            siteId: site.id, siteName: site.name, appVersion: Self.appVersion(.main),
            packVersion: ruleStatus?.packVersion ?? 0, rulesSource: source, health: health))
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

    private static func appVersion(_ bundle: Bundle) -> String {
        bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
    }

    private static func defaultCacheURL() -> URL { supportURL("rulepack.cache.json") }

    private static func supportURL(_ name: String) -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(name)
    }

    // MARK: Onboarding

    func completeOnboarding() {
        defaults.set(true, forKey: Self.onboardingKey)
        showOnboarding = false
    }

    // MARK: Shield

    /// The simulator and previews use the fake; a device uses Family Controls.
    private static func makeShield() -> ShieldController {
        #if targetEnvironment(simulator) || !canImport(FamilyControls)
        return FakeShieldController()
        #else
        return FamilyShieldController()
        #endif
    }

    var shieldAuthorization: ShieldAuthorization {
        _ = shieldVersion
        return shield.authorization
    }

    var shieldHasSelection: Bool {
        _ = shieldVersion
        return shield.hasSelection
    }

    func requestShieldAccess() async {
        try? await shield.requestAuthorization()
        shieldVersion += 1
    }

    /// Turning on only tightens, so it applies at once. Turning off must go through the gate first.
    func setShieldEnabled(_ on: Bool) {
        shieldEnabled = on
        defaults.set(on, forKey: Self.shieldEnabledKey)
        shield.setEnabled(on)
        reconcileShield()
    }

    static let postModeMinutes = 15

    var postModeEndsAt: Date? {
        _ = shieldVersion
        guard let ends = shield.postModeEndsAt, ends > Date() else { return nil }
        return ends
    }

    /// Lifts the shield for `postModeMinutes`. The caller shows the friction gate first.
    /// Returns false when it could not be scheduled, in which case the shield stays up.
    @discardableResult
    func startPostMode() -> Bool {
        defer { shieldVersion += 1 }
        do {
            try shield.startPostMode(minutes: Self.postModeMinutes)
            return true
        } catch {
            return false
        }
    }

    /// Called when the app returns to the foreground, and after any shield change.
    @discardableResult
    func reconcileShield(now: Date = Date()) -> ShieldReconciler.Outcome {
        let outcome = ShieldReconciler.reconcile(shield, enabled: shieldEnabled, now: now)
        shieldVersion += 1
        return outcome
    }

    // MARK: Limits

    enum LimitChangeResult: Equatable {
        case applied
        case needsGate
        case unchanged
    }

    /// Applies a settings change at once if it only tightens. A loosening change is not applied;
    /// the caller shows the friction gate and then calls `commitLimits`.
    @discardableResult
    func proposeLimits(_ new: LimitSettings) -> LimitChangeResult {
        guard new != limits else { return .unchanged }
        if FrictionPolicy.requiresGate(from: limits, to: new) { return .needsGate }
        commitLimits(new)
        return .applied
    }

    /// Applies and saves a settings change without asking. Only call after the gate, or for tightening.
    func commitLimits(_ new: LimitSettings) {
        limits = new
        try? limitsStore.save(new)
        usageVersion += 1
    }

    static let flushEverySeconds = 15
    static let filterPauseSeconds = 5 * 60

    var engine: BudgetEngine { BudgetEngine(settings: limits) }

    /// When the day's budget resets, as shown in the copy: "6:00 am".
    var resetTimeText: String {
        clock.nextReset(after: Date()).formatted(date: .omitted, time: .shortened).lowercased()
    }

    func budgetState(for siteId: String) -> BudgetEngine.State {
        _ = usageVersion
        return engine.state(site: siteId, ledger: ledger)
    }

    func allowedSeconds(for siteId: String) -> Int? {
        _ = usageVersion
        return engine.allowedSeconds(site: siteId, extensionsUsed: ledger.extensions(site: siteId))
    }

    func extensionsLeft(for siteId: String) -> Int {
        _ = usageVersion
        return max(0, limits.maxExtensionsPerDay - ledger.extensions(site: siteId))
    }

    func canPauseFilters(for siteId: String) -> Bool {
        _ = usageVersion
        return engine.canPauseFilters(pausesUsed: ledger.filterPauses(site: siteId))
    }

    /// Counts one second of use, flushing to disk every 15 seconds.
    func tick(siteId: String) {
        ledger.addSeconds(1, site: siteId)
        ticksSinceFlush += 1
        if ticksSinceFlush >= Self.flushEverySeconds { flushUsage() }
        usageVersion += 1
    }

    func flushUsage() {
        ticksSinceFlush = 0
        ledger.flush()
    }

    func grantExtension(siteId: String) {
        ledger.recordExtension(site: siteId)
        usageVersion += 1
    }

    func recordFilterPause(siteId: String) {
        ledger.recordFilterPause(site: siteId)
        usageVersion += 1
    }

    /// The friction countdown. `-qfFastFriction` shortens it to 2 seconds in DEBUG builds only.
    var frictionCountdownSeconds: Int {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("-qfFastFriction") { return 2 }
        #endif
        return limits.frictionCountdownSeconds
    }
}

/// Time display helpers.
enum TimeText {
    /// "14:02"
    static func clock(_ seconds: Int) -> String {
        let s = max(0, seconds)
        return String(format: "%d:%02d", s / 60, s % 60)
    }

    /// "14 min", rounding up so the last partial minute still reads "1 min".
    static func minutes(_ seconds: Int) -> String {
        "\(max(0, (seconds + 59) / 60)) min"
    }
}
