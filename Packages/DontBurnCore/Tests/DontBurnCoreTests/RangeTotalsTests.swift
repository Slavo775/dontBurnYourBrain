@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

private func totals(
    _ span: HistoryRange.Span, _ date: Date, in context: ModelContext, now: Date = friday,
    calendar: Calendar = prague,
) throws -> RangeTotals {
    try RangeTotals(HistoryRange(span, containing: date, calendar: calendar), in: context, now: now, calendar: calendar)
}

private func minutes(_ value: Double) -> TimeInterval {
    value * 60
}

/// Tracked minutes per workspace name.
private func byName(_ totals: [RangeTotals.WorkspaceTotal]) -> [String: TimeInterval] {
    Dictionary(uniqueKeysWithValues: totals.map { ($0.workspace.name, $0.time.tracked / 60) })
}

/// The sample set with five weeks of history, read on ``friday``.
private func sampleHistory(calendar: Calendar = prague) throws -> ModelContext {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: friday)
    try SampleData.seedHistory(into: context, now: friday, calendar: calendar)
    return context
}

// MARK: - The sum of the day views

@Test(arguments: [prague, sundayFirst])
func `with the sample history every week and month equals the sum of its day views`(calendar: Calendar) throws {
    let context = try sampleHistory(calendar: calendar)
    var weeks = [HistoryRange(.week, containing: friday, calendar: calendar)]
    for _ in 1 ... 6 {
        weeks.append(weeks[weeks.count - 1].previous(calendar: calendar))
    }
    let months = [HistoryRange(.month, containing: friday, calendar: calendar), HistoryRange(
        .month, containing: local(10, 15), calendar: calendar,
    )]

    for range in weeks + months {
        let totals = try RangeTotals(range, in: context, now: friday, calendar: calendar)
        try expectMatchesDayViews(totals, in: context, now: friday, calendar: calendar)
    }
}

@Test func `the sample week, last week and month match a count by hand`() throws {
    let context = try sampleHistory()
    let week = try totals(.week, friday, in: context)
    let last = try RangeTotals(.lastWeek(now: friday, calendar: prague), in: context, now: friday, calendar: prague)
    let month = try totals(.month, friday, in: context)

    // 27:45, 31:30 and 92:15, counted by hand from the schedule `seedHistory` documents.
    #expect(byName(week.totals) == ["Acme": 795, "Globex": 660, "Personal": 210])
    #expect(week.total.tracked == minutes(1665))
    #expect(week.total.breaks == minutes(70))
    #expect(byName(last.totals) == ["Acme": 885, "Globex": 795, "Personal": 210])
    #expect(last.total.tracked == minutes(1890))
    #expect(month.total.tracked == minutes(5535))
}

@Test func `last week's totals are the Week view of last week and its bar in the month`() throws {
    let context = try sampleHistory()
    let last = try RangeTotals(.lastWeek(now: friday, calendar: prague), in: context, now: friday, calendar: prague)
    let week = try totals(.week, local(11, 12), in: context)
    let month = try totals(.month, friday, in: context)
    let bar = try #require(month.bars.first { $0.start == last.range.start })

    #expect(!last.isEmpty)
    #expect(last.range == week.range)
    #expect(byName(last.totals) == byName(week.totals))
    #expect(last.total == week.total)
    #expect(byName(bar.totals) == byName(last.totals))
    #expect(bar.total == last.total)
}

// MARK: - Midnight, the month's end and the clocks

@Test func `an entry across midnight counts its part on each day, inside a week and across its end`() throws {
    let desk = try Desk()
    try insert(desk.context, desk.acme, local(11, 17, 23, 30), local(11, 18, 1, 15))
    try insert(desk.context, desk.globex, local(11, 22, 23), local(11, 23, 1))
    let now = local(11, 25, 12)

    let first = try totals(.week, local(11, 17), in: desk.context, now: now)
    let second = try totals(.week, local(11, 23), in: desk.context, now: now)

    #expect(first.bars.map { $0.total.tracked / 60 } == [0, 30, 75, 0, 0, 0, 60])
    #expect(first.total.tracked == minutes(165))
    #expect(second.bars.first?.total.tracked == minutes(60))
    #expect(second.total.tracked == minutes(60))
    // Each entry is counted once over the two weeks.
    #expect(byName(first.totals)["Globex"] == 60)
    #expect(byName(second.totals)["Globex"] == 60)
    try expectMatchesDayViews(first, in: desk.context, now: now, calendar: prague)
    try expectMatchesDayViews(second, in: desk.context, now: now, calendar: prague)
}

@Test func `a week across a month's end is the sum of its days in each month`() throws {
    let desk = try Desk()
    try insert(desk.context, desk.acme, local(10, 31, 10), local(10, 31, 11))
    try insert(desk.context, desk.globex, local(10, 31, 23), local(11, 1, 2))
    try insert(desk.context, desk.personal, local(11, 1, 10), local(11, 1, 10, 45))

    let week = try totals(.week, local(10, 31), in: desk.context)
    let october = try totals(.month, local(10, 15), in: desk.context)
    let november = try totals(.month, local(11, 15), in: desk.context)
    let octoberBar = try #require(october.bars.last)
    let novemberBar = try #require(november.bars.first)

    #expect(week.range.start == local(10, 26))
    #expect(octoberBar.days.map(\.day) == week.range.days(calendar: prague).dropLast())
    #expect(novemberBar.days.map(\.day) == [local(11, 1)])
    #expect(octoberBar.total.tracked == minutes(120))
    #expect(novemberBar.total.tracked == minutes(165))
    #expect(week.total.tracked == octoberBar.total.tracked + novemberBar.total.tracked)
    #expect(byName(week.totals) == ["Acme": 60, "Globex": 180, "Personal": 45])
    #expect(byName(october.totals)["Globex"] == 60)
    #expect(byName(november.totals)["Globex"] == 120)
    for range in [week, october, november] {
        try expectMatchesDayViews(range, in: desk.context, now: friday, calendar: prague)
    }
}

@Test func `the day the clocks go forward has 23 hours, and the day they go back 25`() throws {
    let desk = try Desk()
    try insert(desk.context, desk.acme, local(3, 29), local(3, 30))
    try insert(desk.context, desk.globex, local(10, 25), local(10, 26))

    let spring = try totals(.week, local(3, 29), in: desk.context)
    let autumn = try totals(.week, local(10, 25), in: desk.context)
    let march = try totals(.month, local(3, 29), in: desk.context)
    let october = try totals(.month, local(10, 25), in: desk.context)

    #expect(spring.bars.last?.total.tracked == minutes(23 * 60))
    #expect(spring.total.tracked == minutes(23 * 60))
    #expect(autumn.bars.last?.total.tracked == minutes(25 * 60))
    #expect(autumn.total.tracked == minutes(25 * 60))
    #expect(march.total.tracked == minutes(23 * 60))
    #expect(october.total.tracked == minutes(25 * 60))
    for range in [spring, autumn, march, october] {
        try expectMatchesDayViews(range, in: desk.context, now: friday, calendar: prague)
    }
}

@Test func `an entry over a clock change counts its real length, split at midnight`() throws {
    let desk = try Desk()
    // 3.5 real hours: one before midnight, two to 02:00, then half an hour from 03:00.
    try insert(desk.context, desk.acme, local(3, 28, 23), local(3, 29, 3, 30))
    // 5.5 real hours: half an hour before midnight, then 02:00 to 03:00 twice.
    try insert(desk.context, desk.globex, local(10, 24, 23, 30), local(10, 25, 4))

    let spring = try totals(.week, local(3, 29), in: desk.context)
    let autumn = try totals(.week, local(10, 25), in: desk.context)

    #expect(spring.bars.suffix(2).map { $0.total.tracked / 60 } == [60, 150])
    #expect(autumn.bars.suffix(2).map { $0.total.tracked / 60 } == [30, 300])
    try expectMatchesDayViews(spring, in: desk.context, now: friday, calendar: prague)
    try expectMatchesDayViews(autumn, in: desk.context, now: friday, calendar: prague)
}

// MARK: - What counts

@Test func `breaks are counted apart from work, and a break that does not count is in no number`() throws {
    let desk = try Desk()
    desk.personal.breaksCount = false
    try insert(desk.context, desk.acme, local(11, 16, 9), local(11, 16, 10))
    try insert(desk.context, desk.acme, local(11, 16, 10), local(11, 16, 10, 15), kind: .break)
    try insert(desk.context, desk.globex, local(11, 16, 13), local(11, 16, 13, 30), kind: .meeting)
    try insert(desk.context, desk.personal, local(11, 16, 20), local(11, 16, 20, 30))
    try insert(desk.context, desk.personal, local(11, 16, 20, 30), local(11, 16, 20, 50), kind: .break)

    let week = try totals(.week, friday, in: desk.context)
    let time = Dictionary(uniqueKeysWithValues: week.totals.map { ($0.workspace.name, $0.time) })

    #expect(time["Acme"] == Tally(tracked: minutes(75), breaks: minutes(15)))
    #expect(time["Acme"]?.work == minutes(60))
    #expect(time["Globex"] == Tally(tracked: minutes(30), breaks: 0))
    #expect(time["Personal"] == Tally(tracked: minutes(30), breaks: 0))
    #expect(week.total == Tally(tracked: minutes(135), breaks: minutes(15)))
    #expect(week.total.work == minutes(120))
    #expect(week.bars.first?.total == week.total)
    try expectMatchesDayViews(week, in: desk.context, now: friday, calendar: prague)
}

@Test func `an entry without a project counts under its workspace alone`() throws {
    let desk = try Desk()
    let webShop = Project(name: "Web shop", workspace: desk.acme)
    let mobileApp = Project(name: "Mobile app", workspace: desk.acme, sortOrder: 1)
    desk.context.insert(webShop)
    desk.context.insert(mobileApp)
    try insert(desk.context, desk.acme, local(11, 17, 9), local(11, 17, 10), project: webShop)
    try insert(desk.context, desk.acme, local(11, 17, 10), local(11, 17, 10, 30), project: mobileApp)
    try insert(desk.context, desk.acme, local(11, 17, 10, 30), local(11, 17, 11, 15))
    try insert(desk.context, desk.globex, local(11, 17, 13), local(11, 17, 14))

    let week = try totals(.week, friday, in: desk.context)
    let acme = try #require(week.totals.first)

    #expect(acme.workspace.name == "Acme")
    #expect(acme.time.tracked == minutes(135))
    #expect(acme.projects.map(\.project.name) == ["Web shop", "Mobile app"])
    #expect(acme.projects.map { $0.time.tracked / 60 } == [60, 30])
    #expect(week.totals.last?.projects.isEmpty == true)
    #expect(week.total.tracked == minutes(195))
    try expectMatchesDayViews(week, in: desk.context, now: friday, calendar: prague)
}

@Test func `workspaces come active in their order, then archived, and projects the same way`() throws {
    let desk = try Desk()
    desk.personal.isArchived = true
    desk.personal.sortOrder = -1
    let webShop = Project(name: "Web shop", workspace: desk.acme)
    let mobileApp = Project(name: "Mobile app", workspace: desk.acme, sortOrder: 1)
    webShop.isArchived = true
    desk.context.insert(webShop)
    desk.context.insert(mobileApp)
    try insert(desk.context, desk.personal, local(11, 16, 8), local(11, 16, 9))
    try insert(desk.context, desk.globex, local(11, 16, 9), local(11, 16, 10))
    try insert(desk.context, desk.acme, local(11, 16, 10), local(11, 16, 11), project: webShop)
    try insert(desk.context, desk.acme, local(11, 16, 11), local(11, 16, 12), project: mobileApp)

    let week = try totals(.week, friday, in: desk.context)

    #expect(week.totals.map(\.workspace.name) == ["Acme", "Globex", "Personal"])
    #expect(week.totals.first?.projects.map(\.project.name) == ["Mobile app", "Web shop"])
    #expect(week.bars.first?.totals.map(\.workspace.name) == ["Acme", "Globex", "Personal"])
}

// MARK: - Empty ranges and now

@Test func `a range with no entries is empty and still has a bar for every day`() throws {
    let desk = try Desk()
    try insert(desk.context, desk.acme, local(10, 5, 9), local(10, 5, 10))

    let week = try totals(.week, friday, in: desk.context)
    let month = try totals(.month, local(9, 15), in: desk.context)

    #expect(week.isEmpty)
    #expect(week.bars.count == 7)
    #expect(week.bars.allSatisfy { $0.totals.isEmpty && $0.total == Tally() })
    #expect(week.totals.isEmpty)
    #expect(week.total == Tally())
    #expect(month.isEmpty)
    #expect(month.bars.flatMap(\.days).count == 30)
    #expect(try !totals(.month, local(10, 15), in: desk.context).isEmpty)
}

@Test func `a range whose only entry is a break that does not count is not empty, and counts nothing`() throws {
    let desk = try Desk()
    desk.personal.breaksCount = false
    try insert(desk.context, desk.personal, local(11, 17, 21), local(11, 17, 21, 15), kind: .break)

    let week = try totals(.week, friday, in: desk.context)

    #expect(!week.isEmpty)
    #expect(week.total == Tally())
    #expect(week.totals.map(\.workspace.name) == ["Personal"])
    #expect(week.totals.first?.time == Tally())
}

@Test func `the current week counts today up to now and leaves the days after it empty`() throws {
    let desk = try Desk()
    try insert(desk.context, desk.globex, local(11, 19, 9), local(11, 19, 10))
    // A meeting still to come, from the calendar.
    try insert(desk.context, desk.globex, local(11, 20, 17), local(11, 20, 18), kind: .meeting, source: .calendar)
    try desk.engine.start(desk.acme, minutes: 120, at: local(11, 20, 16))

    let week = try totals(.week, friday, in: desk.context)
    let later = try totals(.week, friday, in: desk.context, now: friday.addingTimeInterval(600))

    #expect(week.bars.map { $0.total.tracked / 60 } == [0, 0, 0, 60, 41, 0, 0])
    #expect(week.bars.suffix(2).allSatisfy { $0.days.allSatisfy(\.items.isEmpty) })
    #expect(week.total.tracked == minutes(101))
    #expect(later.total.tracked == minutes(111))
    try expectMatchesDayViews(week, in: desk.context, now: friday, calendar: prague)
}
