@testable import DontBurnCore
import Foundation
import Testing

private func week(_ date: Date, _ calendar: Calendar = prague) -> HistoryRange {
    HistoryRange(.week, containing: date, calendar: calendar)
}

private func month(_ date: Date, _ calendar: Calendar = prague) -> HistoryRange {
    HistoryRange(.month, containing: date, calendar: calendar)
}

// MARK: - Weeks

@Test(arguments: [prague, sundayFirst])
func `every week of 2026 has seven days from the first weekday, midnight to midnight`(calendar: Calendar) {
    var date = local(1, 1, 12)
    while date < local(1, 1, 12, year: 2027) {
        let range = week(date, calendar)
        let days = range.days(calendar: calendar)
        #expect(range.span == .week)
        #expect(days.count == 7)
        #expect(range.start <= date && date < range.end)
        #expect(calendar.component(.weekday, from: range.start) == calendar.firstWeekday)
        #expect(days.allSatisfy { calendar.startOfDay(for: $0) == $0 })
        #expect(days.first == range.start)
        #expect(calendar.date(byAdding: .day, value: 7, to: range.start) == range.end)
        #expect(range.bars(calendar: calendar) == days.map { [$0] })
        date = calendar.date(byAdding: .day, value: 1, to: date) ?? .distantFuture
    }
}

@Test func `the week starts on the calendar's first weekday`() {
    #expect(week(friday) == week(local(11, 16)))
    #expect(week(friday).start == local(11, 16))
    #expect(week(friday).end == local(11, 23))
    #expect(week(friday, sundayFirst).start == local(11, 15))
    #expect(week(friday, sundayFirst).end == local(11, 22))
    // A Sunday ends a Monday week and starts a Sunday week.
    #expect(week(local(11, 22, 10)).start == local(11, 16))
    #expect(week(local(11, 22, 10), sundayFirst).start == local(11, 22))
}

@Test func `a week's edges are midnights in the calendar's time zone`() {
    #expect(week(local(11, 22, 23, 59, second: 59)).start == local(11, 16))
    #expect(week(local(11, 23)).start == local(11, 23))
    // Monday 00:30 in Prague is still Sunday in UTC, so the UTC week is the one before.
    var utc = prague
    utc.timeZone = .gmt
    let mondayEarly = local(11, 23, 0, 30)
    #expect(week(mondayEarly).start == local(11, 23))
    #expect(week(mondayEarly, utc).start == local(11, 16, 1))
}

@Test func `a week with a clock change still has seven days, of 167 or 169 hours in all`() {
    let spring = week(local(3, 29, 12))
    let autumn = week(local(10, 25, 12))

    #expect(spring.start == local(3, 23))
    #expect(spring.end == local(3, 30))
    #expect(spring.end.timeIntervalSince(spring.start) == 167 * 3600)
    #expect(spring.days(calendar: prague).count == 7)
    #expect(spring.days(calendar: prague).last == local(3, 29))
    #expect(autumn.start == local(10, 19))
    #expect(autumn.end == local(10, 26))
    #expect(autumn.end.timeIntervalSince(autumn.start) == 169 * 3600)
    #expect(autumn.days(calendar: prague).count == 7)
    #expect(autumn.days(calendar: prague).last == local(10, 25))
}

// MARK: - Months

@Test(arguments: 1 ... 12)
func `a month runs from its first midnight to the next month's, one day at a time`(number: Int) {
    let range = month(local(number, 15, 12))
    let days = range.days(calendar: prague)

    #expect(range.span == .month)
    #expect(range.start == local(number, 1))
    #expect(range.end == (number == 12 ? local(1, 1, year: 2027) : local(number + 1, 1)))
    #expect(days.count == prague.range(of: .day, in: .month, for: range.start)?.count)
    #expect(days.allSatisfy { prague.startOfDay(for: $0) == $0 && prague.component(.month, from: $0) == number })
}

@Test(arguments: [prague, sundayFirst])
func `a month's bars are its weeks cut to the month, each day in exactly one`(calendar: Calendar) {
    for number in 1 ... 12 {
        let range = month(local(number, 15, 12), calendar)
        let bars = range.bars(calendar: calendar)

        #expect(bars.flatMap(\.self) == range.days(calendar: calendar))
        for bar in bars {
            guard let first = bar.first else {
                Issue.record("an empty bar")
                continue
            }
            let weekOfBar = week(first, calendar)
            #expect(bar.allSatisfy { weekOfBar.start <= $0 && $0 < weekOfBar.end })
        }
        // Every bar but the first starts on the first weekday, so no week is cut in two inside the month.
        for bar in bars.dropFirst() {
            #expect(bar.first.map { calendar.component(.weekday, from: $0) } == calendar.firstWeekday)
        }
    }
}

@Test func `in November 2026 the end bars hold one day each with Monday first, and five bars come with Sunday first`() {
    let mondayBars = month(friday).bars(calendar: prague)
    let sundayBars = month(friday, sundayFirst).bars(calendar: sundayFirst)

    #expect(mondayBars.map(\.count) == [1, 7, 7, 7, 7, 1])
    #expect(mondayBars.first == [local(11, 1)])
    #expect(mondayBars.last == [local(11, 30)])
    #expect(mondayBars[3].first == local(11, 16))
    #expect(sundayBars.map(\.count) == [7, 7, 7, 7, 2])
    #expect(sundayBars.last == [local(11, 29), local(11, 30)])
    #expect(month(local(2, 10)).bars(calendar: prague).map(\.count) == [1, 7, 7, 7, 6])
    #expect(month(local(3, 10)).bars(calendar: prague).map(\.count) == [1, 7, 7, 7, 7, 2])
}

// MARK: - Previous, next and last week

@Test func `previous goes back one week or one month, across a year's end and a clock change`() {
    #expect(week(friday).previous(calendar: prague) == week(local(11, 9)))
    #expect(week(local(1, 1, 12)).start == local(12, 29, year: 2025))
    #expect(week(local(1, 1, 12)).previous(calendar: prague) == week(local(12, 22, year: 2025)))
    #expect(week(local(4, 1)).previous(calendar: prague) == week(local(3, 29, 12)))
    #expect(month(friday).previous(calendar: prague) == month(local(10, 1)))
    #expect(month(local(1, 20)).previous(calendar: prague).start == local(12, 1, year: 2025))
    #expect(month(local(1, 20)).previous(calendar: prague).end == local(1, 1))
    #expect(week(friday, sundayFirst).previous(calendar: sundayFirst).start == local(11, 8))
}

@Test func `next stops at the week or month that holds now`() {
    let current = week(friday)
    let earlier = current.previous(calendar: prague)

    #expect(current.next(now: friday, calendar: prague) == nil)
    #expect(earlier.next(now: friday, calendar: prague) == current)
    #expect(earlier.previous(calendar: prague).next(now: friday, calendar: prague) == earlier)
    #expect(month(friday).next(now: friday, calendar: prague) == nil)
    #expect(month(local(10, 5)).next(now: friday, calendar: prague) == month(friday))
    #expect(month(local(12, 5, year: 2025)).next(now: friday, calendar: prague) == month(local(1, 5)))
    // A range after now has no next either.
    #expect(week(local(12, 1)).next(now: friday, calendar: prague) == nil)
}

@Test func `next opens the following range once now has reached its end`() {
    let current = week(friday)
    let justBefore = current.end.addingTimeInterval(-1)

    #expect(current.next(now: justBefore, calendar: prague) == nil)
    #expect(current.next(now: current.end, calendar: prague) == week(local(11, 23)))
}

@Test func `last week is the week before the one that holds now`() {
    #expect(HistoryRange.lastWeek(now: friday, calendar: prague) == week(local(11, 9)))
    #expect(HistoryRange.lastWeek(now: friday, calendar: prague).span == .week)
    #expect(HistoryRange.lastWeek(now: local(11, 23), calendar: prague) == week(local(11, 16)))
    #expect(HistoryRange.lastWeek(now: local(11, 22, 23, 59, second: 59), calendar: prague) == week(local(11, 9)))
    #expect(HistoryRange.lastWeek(now: friday, calendar: sundayFirst).start == local(11, 8))
    #expect(HistoryRange.lastWeek(now: friday, calendar: sundayFirst).end == local(11, 15))
}
