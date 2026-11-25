import Foundation

/// A week or a month as History shows it, from midnight to midnight in the
/// calendar's time zone.
///
/// A week starts on the calendar's first weekday and always has seven days. A
/// range may reach past `now`: its later days are simply empty.
public struct HistoryRange: Hashable, Sendable {
    /// How long a range is.
    public enum Span: String, CaseIterable, Sendable {
        /// Seven days from the calendar's first weekday.
        case week
        /// A calendar month.
        case month
    }

    /// Whether the range is a week or a month.
    public let span: Span
    /// Midnight at the start of the first day.
    public let start: Date
    /// Midnight at the start of the day after the last day.
    public let end: Date

    /// The week or the month that contains `date`.
    public init(_ span: Span, containing date: Date, calendar: Calendar) {
        let component: Calendar.Component = span == .week ? .weekOfYear : .month
        let day = calendar.startOfDay(for: date)
        let interval = calendar.dateInterval(of: component, for: date)
            ?? DateInterval(start: day, end: calendar.date(byAdding: component, value: 1, to: day) ?? day)
        self.span = span
        start = interval.start
        end = interval.end
    }

    /// The week before the one that contains `now`, for the sidebar's totals.
    public static func lastWeek(now: Date, calendar: Calendar) -> HistoryRange {
        HistoryRange(.week, containing: now, calendar: calendar).previous(calendar: calendar)
    }

    /// The range of the same span just before this one.
    public func previous(calendar: Calendar) -> HistoryRange {
        HistoryRange(span, containing: calendar.date(byAdding: .day, value: -1, to: start) ?? start, calendar: calendar)
    }

    /// The range of the same span just after this one, or `nil` when this one
    /// contains `now`. Next stops at the current week or month.
    public func next(now: Date, calendar: Calendar) -> HistoryRange? {
        end <= now ? HistoryRange(span, containing: end, calendar: calendar) : nil
    }

    /// The midnight that starts each day of the range, earliest first.
    public func days(calendar: Calendar) -> [Date] {
        var days: [Date] = []
        var day = start
        while day < end {
            days.append(day)
            guard let next = calendar.date(byAdding: .day, value: 1, to: day), next > day else { break }
            day = next
        }
        return days
    }

    /// The days of each bar, earliest first: one day per bar in a week, and in
    /// a month the days of one week that lie inside the month, so each day is
    /// in exactly one bar.
    public func bars(calendar: Calendar) -> [[Date]] {
        let days = days(calendar: calendar)
        guard span == .month else { return days.map { [$0] } }
        var bars: [[Date]] = []
        var week: Date?
        for day in days {
            let dayWeek = calendar.dateInterval(of: .weekOfYear, for: day)?.start
            if dayWeek == week, !bars.isEmpty {
                bars[bars.count - 1].append(day)
            } else {
                bars.append([day])
                week = dayWeek
            }
        }
        return bars
    }
}
