@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// The sample set seeded at `now`, then its history, and the entries the history added.
private struct SampleHistory {
    let context: ModelContext
    let added: [TimeEntry]

    init(now: Date = friday, calendar: Calendar = prague) throws {
        context = try ModelContext(ModelStore.inMemory())
        try SampleData.seed(into: context, now: now)
        let before = try Set(entries(context).map(\.persistentModelID))
        try SampleData.seedHistory(into: context, now: now, calendar: calendar)
        added = try entries(context).filter { !before.contains($0.persistentModelID) }
    }
}

/// What a row of the history holds, to compare two seedings.
private func rows(_ entries: [TimeEntry]) -> [String] {
    entries.map {
        [
            $0.start.formatted(.iso8601), $0.end?.formatted(.iso8601) ?? "", $0.kindRaw, $0.sourceRaw,
            $0.workspace?.name ?? "", $0.project?.name ?? "", $0.note,
        ].joined(separator: "|")
    }
}

/// Times to seed at: a Friday afternoon, just after midnight, a Sunday night,
/// the day the clocks go back and the morning after they go forward.
private let nows = [
    friday, local(11, 25, 0, 10), local(11, 22, 23, 59), local(10, 25, 12), local(3, 30, 1, 30), local(11, 23, 2, 30),
]

@Test func `the history uses only Acme, Globex and Personal and their projects, and adds neither`() throws {
    let history = try SampleHistory()

    #expect(try history.context.fetchCount(FetchDescriptor<Workspace>()) == 3)
    #expect(try history.context.fetchCount(FetchDescriptor<Project>()) == 5)
    #expect(history.added.count > 100)
    for entry in history.added {
        #expect(["Acme", "Globex", "Personal"].contains(entry.workspace?.name ?? ""))
        if let project = entry.project {
            #expect(throws: Never.self) { try project.checkAssignable(to: entry.workspace) }
        }
    }
}

@Test func `the history is the same for the same time, whichever day starts the week`() throws {
    let first = try SampleHistory()
    let second = try SampleHistory()
    let sunday = try SampleHistory(calendar: sundayFirst)

    #expect(rows(first.added) == rows(second.added))
    #expect(rows(first.added) == rows(sunday.added))
}

@Test func `seeding the history a second time adds nothing`() throws {
    let history = try SampleHistory()
    let count = try entries(history.context).count

    try SampleData.seedHistory(into: history.context, now: friday, calendar: prague)

    #expect(try entries(history.context).count == count)
}

@Test func `without the sample workspaces the history adds nothing`() throws {
    let context = try ModelContext(ModelStore.inMemory())

    try SampleData.seedHistory(into: context, now: friday, calendar: prague)

    #expect(try entries(context).isEmpty)
}

@Test(arguments: nows)
func `the history is finished, overlaps nothing and ends at least three hours before now`(now: Date) throws {
    let history = try SampleHistory(now: now)
    let today = prague.startOfDay(for: now)
    let firstDay = try #require(prague.date(byAdding: .day, value: -35, to: today))

    for entry in history.added {
        let end = try #require(entry.end)
        #expect(entry.start < end)
        #expect(end <= now.addingTimeInterval(-3 * 3600))
        #expect(entry.start >= firstDay)
        #expect(entry.start < today)
    }
    let all = try entries(history.context)
    for (earlier, later) in zip(all, all.dropFirst()) {
        #expect((earlier.end ?? now) <= later.start, "entries overlap")
    }
}

@Test(arguments: TimerScenario.allCases)
func `no timer scenario on the sample history leaves overlapping entries`(scenario: TimerScenario) throws {
    let history = try SampleHistory()

    try scenario.apply(to: history.context, now: friday)

    let all = try entries(history.context)
    #expect(all.count { $0.end == nil } <= 1)
    for (earlier, later) in zip(all, all.dropFirst()) {
        #expect((earlier.end ?? friday) <= later.start, "\(scenario.rawValue): entries overlap")
    }
}

@Test func `the history covers every weekday of five weeks and leaves Saturdays empty`() throws {
    let history = try SampleHistory()
    let days = Dictionary(grouping: history.added) { prague.startOfDay(for: $0.start) }

    for back in 1 ... 35 {
        let day = try #require(prague.date(byAdding: .day, value: -back, to: prague.startOfDay(for: friday)))
        let weekday = prague.component(.weekday, from: day)
        #expect((days[day] ?? []).isEmpty == (weekday == 7), "\(back) days back")
    }
    #expect(Set(history.added.map(\.kind)) == Set(TimeEntryKind.allCases))
    #expect(history.added.contains { $0.workspace?.name == "Personal" && $0.kind == .break })
    #expect(history.added.contains { $0.workspace?.name == "Acme" && $0.project == nil && $0.kind == .work })
    #expect(history.added.contains { $0.workspace?.name == "Acme" && $0.project != nil })
}

@Test func `one entry crosses midnight, three days back, from Personal`() throws {
    let history = try SampleHistory()

    let crossing = history.added.filter { entry in
        entry.end.map { !prague.isDate(entry.start, inSameDayAs: $0) } ?? false
    }

    #expect(crossing.count == 1)
    #expect(crossing.first?.start == local(11, 17, 23, 15))
    #expect(crossing.first?.end == local(11, 18, 0, 45))
    #expect(crossing.first?.workspace?.name == "Personal")
}

@Test func `the note a CSV file must quote is on the latest weekday's first Acme entry`() throws {
    let note = "Checkout, \"the redirect\" again\nthen the notes"

    let onFriday = try SampleHistory().added.filter { $0.note == note }
    // At 14:00 on Thursday the sample set's manual entry lies on Wednesday at 09:00, so Tuesday's gets the note.
    let onThursday = try SampleHistory(now: local(11, 19, 14)).added.filter { $0.note == note }

    #expect(onFriday.map(\.start) == [local(11, 19, 9)])
    #expect(onFriday.first?.workspace?.name == "Acme")
    #expect(onThursday.map(\.start) == [local(11, 17, 9)])
}
