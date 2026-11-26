@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

@discardableResult
private func split(_ entry: TimeEntry, at time: Date, in desk: Desk, now: Date = nine) throws -> TimeEntry {
    try EntryEditor(context: desk.context).split(entry, at: time, now: now, calendar: prague)
}

/// Each entry's start and end, earliest first.
private func spans(_ context: ModelContext) throws -> [DateInterval] {
    try entries(context).map { DateInterval(start: $0.start, end: $0.end ?? .distantFuture) }
}

// MARK: - The two halves

@Test func `a split leaves two entries that cover exactly the old one, with all its fields`() throws {
    let desk = try Desk()
    let webShop = Project(name: "Web shop", workspace: desk.acme)
    desk.context.insert(webShop)
    let entry = try insert(
        desk.context, desk.acme, at(-90), at(-30), kind: .meeting, project: webShop,
        note: "Planning, \"Q3\"", source: .calendar,
    )

    let second = try split(entry, at: at(-50), in: desk)

    #expect(entry.end == at(-50))
    #expect(second.start == at(-50))
    #expect(second.end == at(-30))
    let stored = try entries(desk.restarted().context)
    #expect(stored.map(\.start) == [at(-90), at(-50)])
    #expect(stored.map(\.end) == [at(-50), at(-30)])
    for half in stored {
        #expect(half.workspace?.name == "Acme")
        #expect(half.project?.name == "Web shop")
        #expect(half.kind == .meeting)
        #expect(half.source == .calendar)
        #expect(half.note == "Planning, \"Q3\"")
        #expect(half.block == nil)
    }
    try expectHistoryKeepsRules(desk.context)
}

@Test func `on the start's day the cut takes the start's seconds in the chosen minute, and the halves meet`() throws {
    let desk = try Desk()
    let start = at(-90).addingTimeInterval(30)
    let end = at(-30).addingTimeInterval(20)
    let entry = try insert(desk.context, desk.acme, start, end)
    let cut = at(-50).addingTimeInterval(30)

    let second = try split(entry, at: at(-50).addingTimeInterval(45), in: desk)

    #expect(try spans(desk.context) == [DateInterval(start: start, end: cut), DateInterval(start: cut, end: end)])
    #expect(second.start == cut)
}

@Test func `the halves of a finished block keep the block and the timer's rules`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 60, at: at(-120))
    // The ten-minute break ends by itself at -90, and work goes on.
    try desk.engine.startBreak(minutes: 10, at: at(-100))
    try desk.engine.end(at: at(-70))
    let before = try entries(desk.context)
    try #require(before.map(\.kind) == [.work, .break, .work])
    let block = try #require(before[0].block)

    try split(before[1], at: at(-95), in: desk)
    try split(before[2], at: at(-80), in: desk)

    let after = try entries(desk.context)
    #expect(after.map(\.kind) == [.work, .break, .break, .work, .work])
    #expect(after.allSatisfy { $0.block === block })
    #expect(block.entries?.count == 5)
    try expectHistoryKeepsRules(desk.context)
}

@Test func `a half keeps a project that is no longer tracked`() throws {
    let desk = try Desk()
    let sideProject = Project(name: "Side project", workspace: desk.personal)
    desk.context.insert(sideProject)
    let entry = try insert(desk.context, desk.personal, at(-90), at(-30))
    try entry.assign(sideProject)
    sideProject.isTimeTracked = false

    let second = try split(entry, at: at(-60), in: desk)

    #expect(entry.project === sideProject)
    #expect(second.project === sideProject)
}

@Test func `each half can then be changed on its own, under the same checks`() throws {
    let desk = try Desk()
    let first = try insert(desk.context, desk.acme, at(-90), at(-30), note: "Review")
    let second = try split(first, at: at(-60), in: desk)
    let editor = EntryEditor(context: desk.context)

    try editor.update(
        second, to: EntryDraft(start: at(-60), end: at(-30), workspace: desk.globex, kind: .break, note: "Coffee"),
        at: nine,
    )

    #expect(first.workspace?.name == "Acme")
    #expect(first.kind == .work)
    #expect(first.note == "Review")
    #expect(throws: EntryChangeError.overlaps(start: at(-90), end: at(-60))) {
        try editor.update(second, to: EntryDraft(start: at(-70), end: at(-30), workspace: desk.globex), at: nine)
    }
    #expect(throws: EntryChangeError.inFuture) {
        try editor.update(first, to: EntryDraft(start: at(-90), end: at(5), workspace: desk.acme), at: nine)
    }
    try editor.delete(first, at: nine)
    #expect(try entries(desk.context).map(\.note) == ["Coffee"])
}

@Test func `a split on whole minutes leaves each day's total as it was, also across midnight`() throws {
    let desk = try Desk()
    // 23:00 to 01:00 in Prague, around the midnight that starts 15 January.
    let entry = try insert(desk.context, desk.acme, at(-660), at(-540))
    let days = [at(-700), nine]
    let before = try days.map { try DayLog(day: $0, in: desk.context, now: nine, calendar: prague).total }

    try split(entry, at: at(-570), in: desk)

    let after = try days.map { try DayLog(day: $0, in: desk.context, now: nine, calendar: prague).total }
    #expect(before == [3600, 3600])
    #expect(after == before)
}

// MARK: - Refusals

@Test func `the running entry and a finished entry of the running block cannot be split`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: at(-60))
    try desk.engine.pause(at: at(-40))
    try desk.engine.resume(at: at(-30))
    let all = try entries(desk.context)
    try #require(all.count == 2)

    for entry in all {
        #expect(throws: EntryChangeError.runningBlock) { try split(entry, at: at(-35), in: desk) }
    }
    #expect(try spans(desk.context) == [
        DateInterval(start: at(-60), end: at(-40)), DateInterval(start: at(-30), end: .distantFuture),
    ])
    #expect(EntryEditor.splitTimes(for: all[1], calendar: prague) == nil)
}

@Test func `an entry of a paused block cannot be split until the block ends`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: at(-60))
    try desk.engine.pause(at: at(-20))
    let entry = try #require(try entries(desk.context).first)

    #expect(throws: EntryChangeError.runningBlock) { try split(entry, at: at(-40), in: desk) }

    try desk.engine.end(at: at(-10))
    try split(entry, at: at(-40), in: desk)
    #expect(try entries(desk.context).count == 2)
}

@Test(arguments: [-90.0, -89.99, -91, -120, -30, -29.5, -10, 30])
func `a split time under a minute from either end, or outside the entry, is refused`(minute: Double) throws {
    let desk = try Desk()
    let entry = try insert(desk.context, desk.acme, at(-90), at(-30))

    #expect(throws: EntryChangeError.splitNotInside) { try split(entry, at: at(minute), in: desk) }
    #expect(try spans(desk.context) == [DateInterval(start: at(-90), end: at(-30))])
}

@Test(arguments: zip([-89.0, -88.5, -31, -30.01], [-89.0, -89, -31, -31]))
func `a split time a minute or more from both ends is taken at its minute`(minute: Double, taken: Double) throws {
    let desk = try Desk()
    let entry = try insert(desk.context, desk.acme, at(-90), at(-30))

    try split(entry, at: at(minute), in: desk)

    #expect(try entries(desk.context).map(\.end) == [at(taken), at(-30)])
}

@Test func `the times offered are the clock minutes whose cut leaves a minute on each side`() throws {
    let desk = try Desk()
    let short = try insert(desk.context, desk.acme, at(-200), at(-198).addingTimeInterval(-1))
    let twoMinutes = try insert(desk.context, desk.acme, at(-190), at(-188))
    let odd = try insert(desk.context, desk.acme, at(-180).addingTimeInterval(30), at(-176).addingTimeInterval(20))

    #expect(EntryEditor.splitTimes(for: short, calendar: prague) == nil)
    #expect(EntryEditor.splitTimes(for: twoMinutes, calendar: prague) == at(-189) ... at(-189))
    #expect(EntryEditor.splitTimes(for: odd, calendar: prague) == at(-179) ... at(-178))
    #expect(throws: EntryChangeError.splitNotInside) { try split(short, at: at(-199), in: desk) }
    // Cut at 30 seconds into it, the minute before the end's own leaves the second half 50 seconds.
    #expect(throws: EntryChangeError.splitNotInside) { try split(odd, at: at(-177), in: desk) }
    try split(twoMinutes, at: at(-189), in: desk)
    try split(odd, at: at(-179), in: desk)
    #expect(try entries(desk.context).count == 5)
}

@Test func `a split whose half would overlap another entry or reach past now is refused, changing nothing`() throws {
    let desk = try Desk()
    let entry = try insert(desk.context, desk.acme, at(-90), at(-30))
    // An overlap the editor would refuse, as an older store or another device may hold.
    try insert(desk.context, desk.globex, at(-50), at(-40))
    let meeting = try insert(desk.context, desk.globex, at(-20), at(30), kind: .meeting, source: .calendar)
    let nobody = try insert(desk.context, nil, at(-300), at(-240))
    let before = try spans(desk.context)

    #expect(throws: EntryChangeError.overlaps(start: at(-50), end: at(-40))) {
        try split(entry, at: at(-80), in: desk)
    }
    #expect(throws: EntryChangeError.inFuture) { try split(meeting, at: at(-10), in: desk) }
    #expect(throws: EntryChangeError.noWorkspace) { try split(nobody, at: at(-270), in: desk) }
    #expect(try spans(desk.restarted().context) == before)
}
