@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// After every test date, so no half reaches past now.
private let later = local(12, 31)

/// One split of an Acme entry on a store of its own.
private struct SplitOutcome {
    /// Where the halves meet, as the first half ends.
    let firstEnd: Date
    /// Where the halves meet, as the second half starts.
    let cut: Date
    /// The old entry's whole minutes, rounded down.
    let whole: Int
    /// Each half's whole minutes, rounded down.
    let halves: [Int]
    /// The day view's minutes on each day the entry touches, before the split.
    let daysBefore: [Int]
    /// The same days after the split.
    let daysAfter: [Int]
}

private func wholeMinutes(_ start: Date, _ end: Date) -> Int {
    Int(end.timeIntervalSince(start) / 60)
}

/// The day view's minutes on each day from the one holding `start` to the one holding `end`.
private func dayMinutes(_ start: Date, _ end: Date, in context: ModelContext) throws -> [Int] {
    var minutes: [Int] = []
    var day = prague.startOfDay(for: start)
    while day < end {
        try minutes.append(Int(DayLog(day: day, in: context, now: later, calendar: prague).total / 60))
        day = prague.date(byAdding: .day, value: 1, to: day) ?? .distantFuture
    }
    return minutes
}

/// Splits an entry from `start` to `end` at `minute` on a fresh store, or `nil` when refused as not inside.
private func splitFresh(_ start: Date, _ end: Date, at minute: Date) throws -> SplitOutcome? {
    let desk = try Desk()
    let entry = try insert(desk.context, desk.acme, start, end)
    let before = try dayMinutes(start, end, in: desk.context)
    let second: TimeEntry
    do {
        second = try EntryEditor(context: desk.context).split(entry, at: minute, now: later, calendar: prague)
    } catch EntryChangeError.splitNotInside {
        return nil
    }
    return try SplitOutcome(
        firstEnd: entry.end ?? .distantFuture, cut: second.start, whole: wholeMinutes(start, end),
        halves: [wholeMinutes(start, second.start), wholeMinutes(second.start, end)],
        daysBefore: before, daysAfter: dayMinutes(start, end, in: desk.context),
    )
}

/// Checks that the halves meet in the chosen clock minute, keep at least a
/// minute each, and lose no minute from the halves or from any day.
private func expectNoMinuteLost(
    _ outcome: SplitOutcome?, at minute: Date, sourceLocation: SourceLocation = #_sourceLocation,
) {
    guard let outcome else {
        Issue.record("the split was refused", sourceLocation: sourceLocation)
        return
    }
    #expect(outcome.firstEnd == outcome.cut, sourceLocation: sourceLocation)
    #expect(prague.dateInterval(of: .minute, for: outcome.cut)?.start == minute, sourceLocation: sourceLocation)
    #expect(outcome.halves.allSatisfy { $0 >= 1 }, sourceLocation: sourceLocation)
    #expect(outcome.halves.reduce(0, +) == outcome.whole, sourceLocation: sourceLocation)
    #expect(outcome.daysAfter == outcome.daysBefore, sourceLocation: sourceLocation)
}

// MARK: - Where the cut lies

@Test func `the cut counts whole minutes from the start on its day, and back from the end on a later day`() throws {
    // 9:00:30 to 10:29:50, 89 whole minutes.
    let sameDay = try splitFresh(
        local(11, 17, 9, 0, second: 30), local(11, 17, 10, 29, second: 50), at: local(11, 17, 9, 45),
    )
    // 23:00:30 to 1:00:20, 119 whole minutes: 59 on the first day, 60 on the next.
    let nextDay = try splitFresh(
        local(11, 17, 23, 0, second: 30), local(11, 18, 1, 0, second: 20), at: local(11, 18, 0, 30),
    )

    #expect(sameDay?.cut == local(11, 17, 9, 45, second: 30))
    #expect(sameDay?.halves == [45, 44])
    #expect(nextDay?.cut == local(11, 18, 0, 30, second: 20))
    #expect(nextDay?.halves == [89, 30])
    #expect(nextDay?.daysAfter == [59, 60])
    expectNoMinuteLost(sameDay, at: local(11, 17, 9, 45))
    expectNoMinuteLost(nextDay, at: local(11, 18, 0, 30))
}

@Test(arguments: [20, 30, 50])
func `across midnight no minute is lost on either side, the end's seconds below, at or above the start's`(
    endSecond: Int,
) throws {
    let start = local(11, 17, 23, 0, second: 30)
    let end = local(11, 18, 1, 0, second: endSecond)
    let minutes = [
        local(11, 17, 23, 1), local(11, 17, 23, 30), local(11, 17, 23, 59),
        local(11, 18), local(11, 18, 0, 30), local(11, 18, 0, 59),
    ]

    for minute in minutes {
        try expectNoMinuteLost(splitFresh(start, end, at: minute), at: minute)
    }
}

@Test func `a cut at 23:59 takes the start's seconds, and one at 0:00 the end's`() throws {
    let start = local(11, 17, 22, 0, second: 40)
    let end = local(11, 18, 2, 0, second: 15)

    let lastMinute = try splitFresh(start, end, at: local(11, 17, 23, 59))
    let midnight = try splitFresh(start, end, at: local(11, 18))

    #expect(lastMinute?.cut == local(11, 17, 23, 59, second: 40))
    #expect(midnight?.cut == local(11, 18, 0, 0, second: 15))
    expectNoMinuteLost(lastMinute, at: local(11, 17, 23, 59))
    expectNoMinuteLost(midnight, at: local(11, 18))
}

@Test func `an entry on whole minutes is cut at the chosen minute itself, as before`() throws {
    let start = local(11, 17, 23)
    let end = local(11, 18, 1)

    #expect(try splitFresh(start, end, at: local(11, 17, 23, 30))?.cut == local(11, 17, 23, 30))
    #expect(try splitFresh(start, end, at: local(11, 18, 0, 30))?.cut == local(11, 18, 0, 30))
    // A start on a whole minute is cut on the minute on its own day, whatever the end's seconds.
    let ragged = try splitFresh(local(11, 17, 9), local(11, 17, 10, 29, second: 50), at: local(11, 17, 9, 45))
    #expect(ragged?.cut == local(11, 17, 9, 45))
    #expect(ragged?.halves == [45, 44])
}

// MARK: - The minutes offered

@Test func `near midnight only the minutes whose cut leaves a minute on each side are offered`() throws {
    let start = local(11, 17, 23, 59, second: 30)
    let end = local(11, 18, 0, 3, second: 10)
    let desk = try Desk()
    let entry = try insert(desk.context, desk.acme, start, end)

    #expect(EntryEditor.splitTimes(for: entry, calendar: prague) == local(11, 18, 0, 1) ... local(11, 18, 0, 2))
    // 23:59 is the start's own minute, 0:00 would cut at 0:00:10, 40 seconds in, and 0:03 at the end.
    for minute in [local(11, 17, 23, 58), local(11, 17, 23, 59), local(11, 18), local(11, 18, 0, 3)] {
        #expect(try splitFresh(start, end, at: minute) == nil)
    }
    #expect(try splitFresh(start, end, at: local(11, 18, 0, 1))?.cut == local(11, 18, 0, 1, second: 10))
    #expect(try splitFresh(start, end, at: local(11, 18, 0, 2))?.cut == local(11, 18, 0, 2, second: 10))
}

@Test(arguments: zip(
    [
        local(11, 17, 23, 59, second: 30), local(11, 17, 23, 58, second: 50), local(11, 17, 23, 57, second: 10),
        local(11, 17, 23, 58, second: 20), local(11, 17, 23, 59, second: 59), local(11, 17, 23, 59),
        local(11, 17, 9, 0, second: 30), local(11, 17, 9),
    ],
    [
        local(11, 18, 0, 3, second: 10), local(11, 18, 0, 1, second: 40), local(11, 18, 0, 0, second: 20),
        local(11, 18, 0, 2, second: 20), local(11, 18, 0, 2, second: 1), local(11, 18, 0, 2),
        local(11, 17, 9, 4, second: 20), local(11, 17, 9, 3),
    ],
))
func `exactly the minutes offered split, and none of them loses a minute`(start: Date, end: Date) throws {
    let desk = try Desk()
    let entry = try insert(desk.context, desk.acme, start, end)
    let offered = try #require(EntryEditor.splitTimes(for: entry, calendar: prague))
    var minute = prague.dateInterval(of: .minute, for: start)?.start.addingTimeInterval(-60) ?? start

    while minute <= end.addingTimeInterval(60) {
        let outcome = try splitFresh(start, end, at: minute)
        #expect((outcome != nil) == offered.contains(minute), "\(minute.formatted(.iso8601))")
        if outcome != nil {
            expectNoMinuteLost(outcome, at: minute)
        }
        minute = minute.addingTimeInterval(60)
    }
}

// MARK: - The clocks

@Test func `on the day the clocks go forward no minute is lost, from the start or from the end`() throws {
    // 01:30:30 before the change to 03:30:20 after it: 59 whole minutes.
    let sameDay = try splitFresh(
        local(3, 29, 1, 30, second: 30), local(3, 29, 3, 30, second: 20), at: local(3, 29, 3),
    )
    let acrossMidnight = try splitFresh(
        local(3, 28, 23, 0, second: 30), local(3, 29, 3, 30, second: 20), at: local(3, 29, 1, 30),
    )

    #expect(sameDay?.cut == local(3, 29, 3, 0, second: 30))
    #expect(sameDay?.halves == [30, 29])
    #expect(acrossMidnight?.cut == local(3, 29, 1, 30, second: 20))
    #expect(acrossMidnight?.halves == [149, 60])
    #expect(acrossMidnight?.daysAfter == [59, 150])
    expectNoMinuteLost(sameDay, at: local(3, 29, 3))
    expectNoMinuteLost(acrossMidnight, at: local(3, 29, 1, 30))
}

@Test func `on the day the clocks go back no minute is lost, also in the hour that comes twice`() throws {
    let start = local(10, 24, 23, 0, second: 30)
    let end = local(10, 25, 3, 30, second: 20)
    // 2:30 comes twice: once before the clocks go back and once after.
    let twice = local(10, 25, 2, 30)
    let again = try #require([3600.0, -3600].map(twice.addingTimeInterval).first {
        prague.component(.hour, from: $0) == 2
    })

    let afterChange = try splitFresh(start, end, at: local(10, 25, 3))
    let sameDay = try splitFresh(local(10, 25, 1, 30, second: 30), end, at: local(10, 25, 3))

    #expect(afterChange?.cut == local(10, 25, 3, 0, second: 20))
    #expect(afterChange?.halves == [299, 30])
    #expect(afterChange?.daysAfter == [59, 270])
    #expect(sameDay?.cut == local(10, 25, 3, 0, second: 30))
    #expect(sameDay?.halves == [150, 29])
    expectNoMinuteLost(afterChange, at: local(10, 25, 3))
    expectNoMinuteLost(sameDay, at: local(10, 25, 3))
    #expect(prague.component(.minute, from: again) == 30)
    for minute in [twice, again] {
        try expectNoMinuteLost(splitFresh(start, end, at: minute), at: minute)
    }
}

// MARK: - The known limit

@Test func `known limit: an entry over a day, cut on its middle day with the end's seconds, loses one there`() throws {
    // Monday 22:00 to Wednesday 1:00:20, cut on Tuesday at noon, 20 seconds in.
    let outcome = try #require(
        try splitFresh(local(11, 16, 22), local(11, 18, 1, 0, second: 20), at: local(11, 17, 12)),
    )

    #expect(outcome.cut == local(11, 17, 12, 0, second: 20))
    #expect(outcome.halves.reduce(0, +) == outcome.whole)
    #expect(outcome.daysBefore == [120, 1440, 60])
    #expect(outcome.daysAfter == [120, 1439, 60])
}
