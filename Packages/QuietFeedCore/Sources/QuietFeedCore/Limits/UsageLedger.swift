import Foundation

public struct DayUsage: Codable, Equatable, Sendable {
    public var day: String
    public var secondsBySite: [String: Int] = [:]
    public var extensionsBySite: [String: Int] = [:]
    public var filterPausesBySite: [String: Int] = [:]

    public init(day: String) {
        self.day = day
    }
}

/// Owns per-day usage, persists it to a JSON file and rolls over at local midnight.
public final class UsageLedger {
    public static let retentionDays = 14

    private let store: JSONFileStore
    private let clock: Clock
    private var days: [DayUsage]
    private var dirty = false

    public init(store: JSONFileStore, clock: Clock = .system) {
        self.store = store
        self.clock = clock
        self.days = store.load([DayUsage].self) ?? []
        rollOver()
    }

    // MARK: Reads

    public var today: DayUsage {
        rollOver()
        return days.first { $0.day == clock.today } ?? DayUsage(day: clock.today)
    }

    public func seconds(site: String) -> Int { today.secondsBySite[site] ?? 0 }
    public func extensions(site: String) -> Int { today.extensionsBySite[site] ?? 0 }
    public func filterPauses(site: String) -> Int { today.filterPausesBySite[site] ?? 0 }

    /// Retained days, oldest first.
    public var history: [DayUsage] { days }

    // MARK: Writes

    public func addSeconds(_ seconds: Int, site: String) {
        guard seconds > 0 else { return }
        mutateToday { $0.secondsBySite[site, default: 0] += seconds }
    }

    public func recordExtension(site: String) {
        mutateToday { $0.extensionsBySite[site, default: 0] += 1 }
        flush()
    }

    public func recordFilterPause(site: String) {
        mutateToday { $0.filterPausesBySite[site, default: 0] += 1 }
        flush()
    }

    /// Writes to disk if anything changed since the last flush.
    public func flush() {
        guard dirty else { return }
        rollOver()
        try? store.save(days)
        dirty = false
    }

    // MARK: Internals

    private func mutateToday(_ change: (inout DayUsage) -> Void) {
        rollOver()
        guard let i = days.firstIndex(where: { $0.day == clock.today }) else { return }
        change(&days[i])
        dirty = true
    }

    /// Ensures an entry exists for today and drops days outside the retention window.
    private func rollOver() {
        let todayString = clock.today
        if !days.contains(where: { $0.day == todayString }) {
            days.append(DayUsage(day: todayString))
            dirty = true
        }
        let cutoffDate = clock.calendar.date(byAdding: .day, value: -(Self.retentionDays - 1), to: clock.now())
            ?? clock.now()
        let cutoff = clock.dayString(for: cutoffDate)
        let kept = days.filter { $0.day >= cutoff }.sorted { $0.day < $1.day }
        if kept.count != days.count || kept != days {
            days = kept
            dirty = true
        }
    }
}
