@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

/// Midnight at the start of 2026-01-15 in UTC, the day of `nine`.
private var midnight: Date {
    utc.startOfDay(for: nine)
}

private func hours(_ value: Double, from date: Date) -> Date {
    date.addingTimeInterval(value * 3600)
}

// MARK: - Midnight

@Test func `an entry across midnight is stored once and shows on each day with its part`() throws {
    let desk = try Desk()
    // 23:00 yesterday to 01:30 today.
    desk.context.insert(TimeEntry(
        workspace: desk.acme, start: hours(-1, from: midnight), end: hours(1.5, from: midnight),
    ))
    try desk.context.save()

    let yesterday = try DayLog(day: hours(-12, from: midnight), in: desk.context, now: nine, calendar: utc)
    let today = try DayLog(day: nine, in: desk.context, now: nine, calendar: utc)

    #expect(try entries(desk.context).count == 1)
    let before = try #require(yesterday.items.first)
    let after = try #require(today.items.first)
    #expect(before.entry === after.entry)
    #expect(before.start == hours(-1, from: midnight))
    #expect(before.end == midnight)
    #expect(before.length == 3600)
    #expect(after.start == midnight)
    #expect(after.end == hours(1.5, from: midnight))
    #expect(after.length == 5400)
    #expect(yesterday.total == 3600)
    #expect(today.total == 5400)
    #expect(yesterday.day == hours(-24, from: midnight))
    #expect(today.day == midnight)
}

@Test func `the day follows the calendar's time zone`() throws {
    let desk = try Desk()
    // 22:00 to 23:00 UTC yesterday, which is 01:00 to 02:00 today in UTC+3.
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-660), end: at(-600)))
    try desk.context.save()
    var plusThree = Calendar(identifier: .gregorian)
    plusThree.timeZone = try #require(TimeZone(secondsFromGMT: 3 * 3600))

    #expect(try DayLog(day: nine, in: desk.context, now: nine, calendar: utc).items.isEmpty)
    #expect(try DayLog(day: nine, in: desk.context, now: nine, calendar: plusThree).items.count == 1)
}

@Test func `entries on other days are left out, and an entry ending at midnight belongs to the day before`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.acme, start: hours(-2, from: midnight), end: midnight))
    desk.context.insert(TimeEntry(
        workspace: desk.acme, start: hours(-30, from: midnight), end: hours(-29, from: midnight),
    ))
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-60), end: at(-30)))
    try desk.context.save()

    let today = try DayLog(day: nine, in: desk.context, now: nine, calendar: utc)

    #expect(today.items.map(\.entry.workspace?.name) == ["Globex"])
    #expect(today.total == 1800)
}

// MARK: - Now

@Test func `the running entry is in the list and counts up to now`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: at(-30))

    let early = try DayLog(day: nine, in: desk.context, now: nine, calendar: utc)
    let later = try DayLog(day: nine, in: desk.context, now: at(10), calendar: utc)

    let item = try #require(early.items.first)
    #expect(item.isRunning)
    #expect(item.end == nine)
    #expect(item.length == 1800)
    #expect(early.total == 1800)
    #expect(later.total == 2400)
    #expect(later.totals.first?.tracked == 2400)
}

@Test func `an entry that ends after now counts only up to now`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-10), end: at(30), kind: .meeting))
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(60), end: at(90), kind: .meeting))
    try desk.context.save()

    let today = try DayLog(day: nine, in: desk.context, now: nine, calendar: utc)

    #expect(today.items.count == 1)
    #expect(today.items.first?.end == nine)
    #expect(today.total == 600)
}

@Test func `a day after today is empty`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: at(-30))

    let tomorrow = try DayLog(day: hours(30, from: midnight), in: desk.context, now: nine, calendar: utc)

    #expect(tomorrow.items.isEmpty)
    #expect(tomorrow.totals.isEmpty)
    #expect(tomorrow.total == 0)
}

// MARK: - Totals

@Test func `totals list active workspaces in order, then archived ones, only those with an entry`() throws {
    let desk = try Desk()
    // Archived and first in the order, so only the archive rule puts it last.
    desk.personal.isArchived = true
    desk.personal.sortOrder = -1
    desk.context.insert(TimeEntry(workspace: desk.personal, start: at(-200), end: at(-190)))
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-180), end: at(-150)))
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-120), end: at(-60)))
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-50), end: at(-40)))
    try desk.context.save()

    let today = try DayLog(day: nine, in: desk.context, now: nine, calendar: utc)
    let expected: [TimeInterval] = [4200, 1800, 600]

    #expect(today.totals.map(\.workspace.name) == ["Acme", "Globex", "Personal"])
    #expect(today.totals.map(\.tracked) == expected)
    #expect(today.total == 6600)
    #expect(today.items.map(\.start) == [at(-200), at(-180), at(-120), at(-50)])
}

@Test func `a break counts only when its workspace counts breaks, and is still listed`() throws {
    let desk = try Desk()
    desk.globex.breaksCount = false
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-60), end: at(-50), kind: .break))
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-40), end: at(-35), kind: .break))
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-30), end: at(-20)))
    try desk.context.save()

    let today = try DayLog(day: nine, in: desk.context, now: nine, calendar: utc)

    #expect(today.items.map(\.counts) == [true, false, true])
    #expect(today.items[1].length == 300)
    #expect(today.totals.map(\.tracked) == [600, 600])
    #expect(today.total == 1200)
}

@Test func `a correction changes the totals at once`() throws {
    let desk = try Desk()
    let entry = TimeEntry(workspace: desk.acme, start: at(-60), end: at(-30))
    desk.context.insert(entry)
    try desk.context.save()
    #expect(try DayLog(day: nine, in: desk.context, now: nine, calendar: utc).total == 1800)

    try EntryEditor(context: desk.context).update(
        entry, to: EntryDraft(start: at(-60), end: at(-15), workspace: desk.globex), at: nine,
    )

    let today = try DayLog(day: nine, in: desk.context, now: nine, calendar: utc)
    #expect(today.total == 2700)
    #expect(today.totals.map(\.workspace.name) == ["Globex"])
}

@Test func `the panel's tracked today is the day log's total`() throws {
    let container = try ModelStore.inMemory()
    let context = ModelContext(container)
    try SampleData.seed(into: context, now: nine)

    let tracked = try CompactPanel.trackedToday(in: context, now: nine, calendar: utc)

    #expect(try tracked == (DayLog(day: nine, in: context, now: nine, calendar: utc).total))
    #expect(tracked > 0)
}

@Test func `the sample data has one manual entry on the day before`() throws {
    let container = try ModelStore.inMemory()
    let context = ModelContext(container)
    try SampleData.seed(into: context, now: nine)

    let yesterday = try DayLog(
        day: DayLog.day(before: nine, calendar: utc), in: context, now: nine, calendar: utc,
    )

    #expect(yesterday.items.map(\.entry.note) == ["Release checklist"])
    #expect(yesterday.items.first?.entry.source == .manual)
}

// MARK: - Moving between days

@Test func `the day before is the previous midnight, from any time of day`() {
    #expect(DayLog.day(before: nine, calendar: utc) == hours(-24, from: midnight))
    #expect(DayLog.day(before: midnight, calendar: utc) == hours(-24, from: midnight))
    #expect(DayLog.day(before: hours(-0.001, from: midnight), calendar: utc) == hours(-48, from: midnight))
}

@Test func `the next earlier day stops before today`() {
    let yesterday = hours(-24, from: midnight)
    let twoDaysAgo = hours(-48, from: midnight)

    #expect(DayLog.earlierDay(after: twoDaysAgo, now: nine, calendar: utc) == yesterday)
    #expect(DayLog.earlierDay(after: hours(5, from: twoDaysAgo), now: nine, calendar: utc) == yesterday)
    #expect(DayLog.earlierDay(after: yesterday, now: nine, calendar: utc) == nil)
    #expect(DayLog.earlierDay(after: midnight, now: nine, calendar: utc) == nil)
    #expect(DayLog.earlierDay(after: yesterday, now: midnight, calendar: utc) == nil)
}

@Test func `an earlier day can be corrected and gets an entry added by hand`() throws {
    let desk = try Desk()
    let yesterday = hours(-24, from: midnight)
    let editor = EntryEditor(context: desk.context)

    let added = try editor.add(
        EntryDraft(start: hours(9, from: yesterday), end: hours(10, from: yesterday), workspace: desk.acme), at: nine,
    )
    try editor.update(
        added, to: EntryDraft(start: hours(9, from: yesterday), end: hours(11, from: yesterday), workspace: desk.acme),
        at: nine,
    )

    let log = try DayLog(day: yesterday, in: desk.context, now: nine, calendar: utc)
    #expect(log.total == 7200)
    #expect(try DayLog(day: nine, in: desk.context, now: nine, calendar: utc).items.isEmpty)
}

// MARK: - Whole minutes

@Test func `rows show whole minutes rounded down and every total is their sum`() throws {
    let desk = try Desk()
    // 39:50, 30:20 and 41:59 for Acme, 20:30 for Globex.
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-200), end: at(-200 + 39 + 50.0 / 60)))
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-150), end: at(-150 + 30 + 20.0 / 60)))
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-110), end: at(-110 + 20.5)))
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-60), end: at(-60 + 41 + 59.0 / 60)))
    try desk.context.save()

    let today = try DayLog(day: nine, in: desk.context, now: nine, calendar: utc)
    let rows: [TimeInterval] = [39 * 60, 30 * 60, 20 * 60, 41 * 60]
    let totals: [TimeInterval] = [110 * 60, 20 * 60]

    #expect(today.items.map(\.length) == rows)
    #expect(today.totals.map(\.tracked) == totals)
    #expect(today.total == 130 * 60)
    #expect(try CompactPanel.trackedToday(in: desk.context, now: nine, calendar: utc) == 130 * 60)
}

@Test func `a running entry counts in whole minutes up to now`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: at(-30.25))

    #expect(try DayLog(day: nine, in: desk.context, now: nine, calendar: utc).total == 30 * 60)
    #expect(try DayLog(day: nine, in: desk.context, now: at(0.2), calendar: utc).total == 30 * 60)
    #expect(try DayLog(day: nine, in: desk.context, now: at(0.8), calendar: utc).total == 31 * 60)
}

@Test(arguments: TimerScenario.allCases)
func `no timer scenario on the sample data leaves overlapping entries`(scenario: TimerScenario) throws {
    let container = try ModelStore.inMemory()
    let context = ModelContext(container)
    let now = Date(timeIntervalSince1970: 1_768_466_490)
    try SampleData.seed(into: context, now: now)
    try scenario.apply(to: context, now: now)

    let all = try entries(context)
    for (earlier, later) in zip(all, all.dropFirst()) {
        #expect((earlier.end ?? now) <= later.start, "\(scenario.rawValue): entries overlap")
    }
}
