import Foundation

public struct BudgetEngine {
    public enum State: Equatable, Sendable {
        case unlimited
        case ok(remaining: Int)
        case warning(remaining: Int)
        case exhausted(canExtend: Bool)
    }

    /// Warning starts when this many seconds or fewer remain.
    public static let warningSeconds = 120

    public var settings: LimitSettings

    public init(settings: LimitSettings) {
        self.settings = settings
    }

    /// Seconds allowed today: budget plus extensions. Nil when the site has no limit.
    public func allowedSeconds(site: String, extensionsUsed: Int) -> Int? {
        let budget = settings.budgetMinutes(site: site)
        guard budget > 0 else { return nil }
        return budget * 60 + extensionsUsed * settings.extensionMinutes * 60
    }

    public func state(site: String, usedSeconds: Int, extensionsUsed: Int) -> State {
        guard let allowed = allowedSeconds(site: site, extensionsUsed: extensionsUsed) else { return .unlimited }
        let remaining = allowed - usedSeconds
        if remaining <= 0 {
            return .exhausted(canExtend: extensionsUsed < settings.maxExtensionsPerDay)
        }
        return remaining <= Self.warningSeconds ? .warning(remaining: remaining) : .ok(remaining: remaining)
    }

    public func state(site: String, ledger: UsageLedger) -> State {
        state(site: site, usedSeconds: ledger.seconds(site: site), extensionsUsed: ledger.extensions(site: site))
    }

    public func canPauseFilters(pausesUsed: Int) -> Bool {
        pausesUsed < settings.maxFilterPausesPerDay
    }
}
