import Foundation

public struct LimitSettings: Codable, Equatable, Sendable {
    public static let defaultBudgetMinutes = 20
    public static let defaultPhrase = "I am choosing to scroll"

    /// Minutes per site; 0 means no limit.
    public var dailyBudgetMinutesBySite: [String: Int]
    public var extensionMinutes: Int
    public var maxExtensionsPerDay: Int
    public var maxFilterPausesPerDay: Int
    public var frictionCountdownSeconds: Int
    public var frictionPhrase: String

    public init(
        dailyBudgetMinutesBySite: [String: Int] = [
            "instagram": LimitSettings.defaultBudgetMinutes,
            "youtube": LimitSettings.defaultBudgetMinutes,
            "facebook": LimitSettings.defaultBudgetMinutes,
        ],
        extensionMinutes: Int = 5,
        maxExtensionsPerDay: Int = 2,
        maxFilterPausesPerDay: Int = 1,
        frictionCountdownSeconds: Int = 30,
        frictionPhrase: String = LimitSettings.defaultPhrase
    ) {
        self.dailyBudgetMinutesBySite = dailyBudgetMinutesBySite
        self.extensionMinutes = extensionMinutes
        self.maxExtensionsPerDay = maxExtensionsPerDay
        self.maxFilterPausesPerDay = maxFilterPausesPerDay
        self.frictionCountdownSeconds = frictionCountdownSeconds
        self.frictionPhrase = frictionPhrase
    }

    /// Missing sites get the default budget.
    public func budgetMinutes(site: String) -> Int {
        dailyBudgetMinutesBySite[site] ?? Self.defaultBudgetMinutes
    }
}
