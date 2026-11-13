import Foundation

/// A source of time plus the calendar that defines "a day". Tests inject their own.
public struct Clock {
    public var now: () -> Date
    public var calendar: Calendar

    public init(now: @escaping () -> Date = Date.init, calendar: Calendar = .current) {
        self.now = now
        self.calendar = calendar
    }

    public static var system: Clock { Clock() }

    /// Local calendar day as "yyyy-MM-dd".
    public func dayString(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public var today: String { dayString(for: now()) }
}
