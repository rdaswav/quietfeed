import Foundation

/// A source of time plus the calendar that defines "a day". Tests inject their own.
/// A day can start later than midnight (the design says it resets at 6:00 am), so scrolling at 1 am
/// still counts toward the day that began the morning before.
public struct Clock {
    public var now: () -> Date
    public var calendar: Calendar
    /// Hour the day starts, 0 to 23. 0 is plain midnight.
    public var dayStartHour: Int

    /// The hour the app uses for real: the budget resets at 6:00 am.
    public static let defaultDayStartHour = 6

    public init(now: @escaping () -> Date = Date.init, calendar: Calendar = .current, dayStartHour: Int = 0) {
        self.now = now
        self.calendar = calendar
        self.dayStartHour = min(23, max(0, dayStartHour))
    }

    public static var system: Clock { Clock(dayStartHour: defaultDayStartHour) }

    private func shifted(_ date: Date) -> Date {
        date.addingTimeInterval(-TimeInterval(dayStartHour) * 3600)
    }

    /// Local day as "yyyy-MM-dd", where the day begins at `dayStartHour`.
    public func dayString(for date: Date) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: shifted(date))
        return String(format: "%04d-%02d-%02d", c.year ?? 0, c.month ?? 0, c.day ?? 0)
    }

    public var today: String { dayString(for: now()) }

    /// The next moment a new day begins, after `date`.
    public func nextReset(after date: Date) -> Date {
        let startOfShiftedDay = calendar.startOfDay(for: shifted(date))
        let nextShiftedStart = calendar.date(byAdding: .day, value: 1, to: startOfShiftedDay) ?? startOfShiftedDay
        return nextShiftedStart.addingTimeInterval(TimeInterval(dayStartHour) * 3600)
    }
}
