import Foundation

/// The pure parts of the friction gate: what needs it, phrase matching and loosening checks.
public enum FrictionPolicy {
    public enum Action: Equatable, Sendable {
        case extendTime
        case pauseFilters
        case raiseBudget(site: String)
        case raiseExtensionLength
        case raiseMaxExtensions
        case raiseMaxFilterPauses
        case shortenCountdown
        case changePhrase
        case changeShieldSelection
        case startPostMode
        case lowerBudget(site: String)
        case lengthenCountdown
    }

    /// The table in Architecture 6.3: only lowering a budget or lengthening the countdown is free.
    public static func needsGate(_ action: Action) -> Bool {
        switch action {
        case .lowerBudget, .lengthenCountdown: return false
        default: return true
        }
    }

    /// Case-insensitive, ignoring leading and trailing whitespace.
    public static func phraseMatches(typed: String, phrase: String) -> Bool {
        let a = typed.trimmingCharacters(in: .whitespacesAndNewlines)
        let b = phrase.trimmingCharacters(in: .whitespacesAndNewlines)
        return !b.isEmpty && a.caseInsensitiveCompare(b) == .orderedSame
    }

    /// Every loosening action implied by changing `old` into `new`, or empty if the change only tightens.
    public static func loosenings(from old: LimitSettings, to new: LimitSettings) -> [Action] {
        var out: [Action] = []
        for site in Set(old.dailyBudgetMinutesBySite.keys).union(new.dailyBudgetMinutesBySite.keys).sorted() {
            if effective(new.budgetMinutes(site: site)) > effective(old.budgetMinutes(site: site)) {
                out.append(.raiseBudget(site: site))
            }
        }
        if new.extensionMinutes > old.extensionMinutes { out.append(.raiseExtensionLength) }
        if new.maxExtensionsPerDay > old.maxExtensionsPerDay { out.append(.raiseMaxExtensions) }
        if new.maxFilterPausesPerDay > old.maxFilterPausesPerDay { out.append(.raiseMaxFilterPauses) }
        if new.frictionCountdownSeconds < old.frictionCountdownSeconds { out.append(.shortenCountdown) }
        if new.frictionPhrase != old.frictionPhrase { out.append(.changePhrase) }
        return out
    }

    public static func requiresGate(from old: LimitSettings, to new: LimitSettings) -> Bool {
        loosenings(from: old, to: new).contains(where: needsGate)
    }

    /// A budget of 0 means no limit, which is looser than any number.
    private static func effective(_ minutes: Int) -> Int {
        minutes == 0 ? Int.max : minutes
    }
}
