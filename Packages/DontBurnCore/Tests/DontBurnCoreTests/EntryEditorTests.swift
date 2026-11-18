@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// A desk with one finished entry of a running block and the block's running entry.
///
/// Acme's block starts at 08:00 for two hours. Work runs 08:00 to 08:20, then
/// a pause, then work again from 08:30 on. It is 09:00.
private struct RunningBlock {
    let desk: Desk
    let finished: TimeEntry
    let running: TimeEntry

    init() throws {
        desk = try Desk()
        try desk.engine.start(desk.acme, minutes: 120, at: at(-60))
        try desk.engine.pause(at: at(-40))
        try desk.engine.resume(at: at(-30))
        let all = try entries(desk.context)
        try #require(all.count == 2)
        finished = all[0]
        running = all[1]
    }
}

// MARK: - Refusals

@Test func `a change is refused without a workspace before any other rule`() throws {
    let desk = try Desk()
    let draft = EntryDraft(start: at(30), end: at(10), workspace: nil)
    #expect(throws: EntryChangeError.noWorkspace) {
        try EntryEditor(context: desk.context).add(draft, at: nine)
    }
}

@Test(arguments: [0.0, -5.0])
func `a change is refused when the end is not after the start, before the future check`(length: Double) throws {
    let desk = try Desk()
    let draft = EntryDraft(start: at(30), end: at(30 + length), workspace: desk.acme)
    #expect(throws: EntryChangeError.endNotAfterStart) {
        try EntryEditor(context: desk.context).add(draft, at: nine)
    }
}

@Test func `a change that reaches into the future is refused before the overlap check`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-30), end: at(-10)))
    try desk.context.save()
    let draft = EntryDraft(start: at(-20), end: at(0.1), workspace: desk.acme)
    #expect(throws: EntryChangeError.inFuture) {
        try EntryEditor(context: desk.context).add(draft, at: nine)
    }
}

@Test func `an entry may end exactly now`() throws {
    let desk = try Desk()
    try EntryEditor(context: desk.context).add(EntryDraft(start: at(-20), end: nine, workspace: desk.acme), at: nine)
    #expect(try entries(desk.context).count == 1)
}

@Test func `an overlap is refused and names the other entry's range`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-60), end: at(-30)))
    try desk.context.save()
    let editor = EntryEditor(context: desk.context)

    #expect(throws: EntryChangeError.overlaps(start: at(-60), end: at(-30))) {
        try editor.add(EntryDraft(start: at(-35), end: at(-20), workspace: desk.acme), at: nine)
    }
    #expect(throws: EntryChangeError.overlaps(start: at(-60), end: at(-30))) {
        try editor.add(EntryDraft(start: at(-90), end: at(0), workspace: desk.acme), at: nine)
    }
    #expect(throws: EntryChangeError.overlaps(start: at(-60), end: at(-30))) {
        try editor.add(EntryDraft(start: at(-50), end: at(-40), workspace: desk.acme), at: nine)
    }
    #expect(try entries(desk.context).count == 1)
}

@Test func `entries that only touch do not overlap`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-60), end: at(-30)))
    try desk.context.save()
    let editor = EntryEditor(context: desk.context)

    try editor.add(EntryDraft(start: at(-90), end: at(-60), workspace: desk.acme), at: nine)
    try editor.add(EntryDraft(start: at(-30), end: at(-10), workspace: desk.acme), at: nine)

    #expect(try entries(desk.context).count == 3)
    try expectHistoryKeepsRules(desk.context)
}

@Test func `the running entry counts up to now in the overlap check`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: at(-30))
    let editor = EntryEditor(context: desk.context)

    #expect(throws: EntryChangeError.overlaps(start: at(-30), end: nine)) {
        try editor.add(EntryDraft(start: at(-10), end: at(-5), workspace: desk.globex), at: nine)
    }
    try editor.add(EntryDraft(start: at(-60), end: at(-30), workspace: desk.globex), at: nine)
    #expect(try entries(desk.context).count == 2)
}

@Test func `an entry of no length overlaps nothing`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-20), end: at(-20)))
    try desk.context.save()

    try EntryEditor(context: desk.context).add(EntryDraft(start: at(-25), end: at(-15), workspace: desk.acme), at: nine)

    #expect(try entries(desk.context).count == 2)
}

@Test func `a refused correction leaves the entry as it was`() throws {
    let desk = try Desk()
    let first = TimeEntry(workspace: desk.acme, start: at(-90), end: at(-60), note: "Standup")
    desk.context.insert(first)
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-50), end: at(-40)))
    try desk.context.save()
    let editor = EntryEditor(context: desk.context)

    for draft in [
        EntryDraft(start: at(-90), end: at(-45), workspace: desk.acme, note: "Changed"),
        EntryDraft(start: at(-90), end: at(-95), workspace: desk.acme, note: "Changed"),
        EntryDraft(start: at(-90), end: at(5), workspace: desk.acme, note: "Changed"),
        EntryDraft(start: at(-90), end: at(-60), workspace: nil, note: "Changed"),
    ] {
        #expect(throws: EntryChangeError.self) { try editor.update(first, to: draft, at: nine) }
    }

    let stored = try entries(desk.restarted().context)[0]
    #expect(stored.start == at(-90))
    #expect(stored.end == at(-60))
    #expect(stored.note == "Standup")
    #expect(stored.workspace?.name == "Acme")
}

// MARK: - Corrections

@Test func `a correction is saved and does not overlap the entry's own old range`() throws {
    let desk = try Desk()
    let entry = TimeEntry(workspace: desk.acme, start: at(-90), end: at(-60))
    desk.context.insert(entry)
    try desk.context.save()

    try EntryEditor(context: desk.context).update(
        entry,
        to: EntryDraft(start: at(-80), end: at(-50), workspace: desk.acme, kind: .break, note: "Coffee"),
        at: nine,
    )

    let stored = try entries(desk.restarted().context)[0]
    #expect(stored.start == at(-80))
    #expect(stored.end == at(-50))
    #expect(stored.kind == .break)
    #expect(stored.note == "Coffee")
}

@Test func `moving an entry to another workspace clears its project, keeping the workspace keeps it`() throws {
    let desk = try Desk()
    let project = Project(name: "Mobile app", workspace: desk.acme)
    desk.context.insert(project)
    let entry = TimeEntry(workspace: desk.acme, start: at(-90), end: at(-60))
    desk.context.insert(entry)
    try entry.assign(project)
    try desk.context.save()
    let editor = EntryEditor(context: desk.context)

    try editor.update(entry, to: EntryDraft(start: at(-90), end: at(-50), workspace: desk.acme), at: nine)
    #expect(entry.project?.name == "Mobile app")

    try editor.update(entry, to: EntryDraft(start: at(-90), end: at(-50), workspace: desk.globex), at: nine)
    #expect(entry.workspace?.name == "Globex")
    #expect(entry.project == nil)
}

// MARK: - Adding by hand

@Test func `an entry added by hand is stored as manual, in no block`() throws {
    let desk = try Desk()
    try EntryEditor(context: desk.context).add(
        EntryDraft(start: at(-1500), end: at(-1440), workspace: desk.globex, kind: .work, note: "Review"),
        at: nine,
    )

    let stored = try #require(try entries(desk.restarted().context).first)
    #expect(stored.source == .manual)
    #expect(stored.block == nil)
    #expect(stored.workspace?.name == "Globex")
    #expect(stored.start == at(-1500))
    #expect(stored.end == at(-1440))
    #expect(stored.note == "Review")
}

// MARK: - Deleting

@Test func `a finished entry outside a running block can be deleted`() throws {
    let desk = try Desk()
    let entry = TimeEntry(workspace: desk.acme, start: at(-90), end: at(-60))
    desk.context.insert(entry)
    try desk.context.save()

    try EntryEditor(context: desk.context).delete(entry, at: nine)

    #expect(try entries(desk.restarted().context).isEmpty)
}

// MARK: - The running block

@Test func `every entry of the running block takes a note only`() throws {
    let fixture = try RunningBlock()
    let (desk, finished, running) = (fixture.desk, fixture.finished, fixture.running)
    #expect(EntryEditor.isNoteOnly(finished))
    #expect(EntryEditor.isNoteOnly(running))
    let editor = EntryEditor(context: desk.context)

    for entry in [finished, running] {
        let asStored = EntryDraft(entry, now: nine)
        var moved = asStored
        moved.start = entry.start.addingTimeInterval(-60)
        var otherWorkspace = asStored
        otherWorkspace.workspace = desk.globex
        var otherKind = asStored
        otherKind.kind = .break
        for draft in [moved, otherWorkspace, otherKind] {
            #expect(throws: EntryChangeError.runningBlock) { try editor.update(entry, to: draft, at: nine) }
        }
        var noted = asStored
        noted.note = "Focus"
        try editor.update(entry, to: noted, at: nine)
        #expect(entry.note == "Focus")
        #expect(throws: EntryChangeError.runningBlock) { try editor.delete(entry, at: nine) }
    }

    var shortened = EntryDraft(finished, now: nine)
    shortened.end = at(-45)
    #expect(throws: EntryChangeError.runningBlock) { try editor.update(finished, to: shortened, at: nine) }
    // A running entry's form holds the moment it opened as its end, which a later save ignores.
    var runningLater = EntryDraft(running, now: at(-1))
    runningLater.note = "Later"
    try editor.update(running, to: runningLater, at: nine)
    #expect(running.end == nil)
    #expect(try entries(desk.restarted().context).map(\.note) == ["Focus", "Later"])
}

@Test func `once the block ends its entries can be corrected and deleted`() throws {
    let fixture = try RunningBlock()
    let (desk, finished, running) = (fixture.desk, fixture.finished, fixture.running)
    try desk.engine.end(at: at(1))
    #expect(!EntryEditor.isNoteOnly(finished))
    #expect(!EntryEditor.isNoteOnly(running))
    let editor = EntryEditor(context: desk.context)

    try editor.update(
        running, to: EntryDraft(start: at(-25), end: at(0), workspace: desk.acme, note: "Wrap up"), at: at(2),
    )
    #expect(running.start == at(-25))
    #expect(running.end == at(0))

    try editor.delete(finished, at: at(2))
    #expect(try entries(desk.restarted().context).count == 1)
}

@Test func `the editor settles the timer first, so a block that ran out frees its entries`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 30, at: at(-120))
    let entry = try #require(try entries(desk.context).first)
    #expect(entry.end == nil)

    // Two hours later the 30-minute block has ended by itself, so the entry is not running any more.
    try EntryEditor(context: desk.context).delete(entry, at: nine)

    #expect(try entries(desk.context).isEmpty)
}

// MARK: - The form's choices

@Test func `the form offers work and break, and keeps an entry's other kind`() {
    #expect(EntryEditor.kindChoices(keeping: nil) == [.work, .break])
    #expect(EntryEditor.kindChoices(keeping: .work) == [.work, .break])
    #expect(EntryEditor.kindChoices(keeping: .break) == [.work, .break])
    #expect(EntryEditor.kindChoices(keeping: .meeting) == [.work, .break, .meeting])
}

@Test func `the form offers the active workspaces, and keeps an entry's archived one at the end`() throws {
    let desk = try Desk()
    let active = [desk.acme, desk.globex]
    desk.personal.isArchived = true

    #expect(EntryEditor.workspaceChoices(active: active, keeping: nil).map(\.name) == ["Acme", "Globex"])
    #expect(EntryEditor.workspaceChoices(active: active, keeping: desk.globex).map(\.name) == ["Acme", "Globex"])
    #expect(
        EntryEditor.workspaceChoices(active: active, keeping: desk.personal).map(\.name)
            == ["Acme", "Globex", "Personal"],
    )
}

@Test func `a draft of a running entry ends now`() throws {
    let fixture = try RunningBlock()
    let (finished, running) = (fixture.finished, fixture.running)
    #expect(EntryDraft(running, now: nine).end == nine)
    #expect(EntryDraft(finished, now: nine).end == at(-40))
}

// MARK: - The free default for a new entry

private var gmt: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

@Test func `with nothing tracked the free stretch ends now, on the whole minute before it`() throws {
    let desk = try Desk()
    let now = at(0.75)

    let free = try EntryEditor(context: desk.context)
        .latestFreeStretch(minutes: 30, endingBy: now, at: now, calendar: gmt)

    #expect(free == DateInterval(start: at(-30), end: at(0)))
}

@Test func `the free stretch ends by the given end when that is before now`() throws {
    let desk = try Desk()
    let free = try EntryEditor(context: desk.context)
        .latestFreeStretch(minutes: 60, endingBy: at(-600), at: nine, calendar: gmt)
    #expect(free == DateInterval(start: at(-660), end: at(-600)))
}

@Test func `the free stretch steps back past the running block and every entry it hits`() throws {
    let desk = try Desk()
    // Work 08:00 to 08:20, a gap of ten minutes, work 08:30:30 to 08:40, and a block running since 08:40.
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-60), end: at(-40)))
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-29.5), end: at(-20)))
    try desk.context.save()
    try desk.engine.start(desk.acme, minutes: 120, at: at(-20))
    let editor = EntryEditor(context: desk.context)

    let short = try editor.latestFreeStretch(minutes: 5, endingBy: nine, at: nine, calendar: gmt)
    let long = try editor.latestFreeStretch(minutes: 30, endingBy: nine, at: nine, calendar: gmt)

    // 08:30:30 rounds down to 08:30, so the ten-minute gap fits five minutes.
    #expect(short == DateInterval(start: at(-35), end: at(-30)))
    #expect(long == DateInterval(start: at(-90), end: at(-60)))
    let interval = try #require(long)
    try editor.add(EntryDraft(start: interval.start, end: interval.end, workspace: desk.personal), at: nine)
}

@Test func `the free stretch gives up after a hundred steps`() throws {
    let desk = try Desk()
    // Back-to-back 40-minute entries up to now: each step skips exactly one.
    for index in 1 ... 101 {
        let end = at(Double(-40 * (index - 1)))
        desk.context.insert(TimeEntry(workspace: desk.acme, start: end.addingTimeInterval(-2400), end: end))
    }
    try desk.context.save()
    let editor = EntryEditor(context: desk.context)

    #expect(try editor.latestFreeStretch(minutes: 30, endingBy: nine, at: nine, calendar: gmt) == nil)
    let earlier = at(-40 * 2)
    #expect(
        try editor.latestFreeStretch(minutes: 30, endingBy: earlier, at: nine, calendar: gmt)
            == DateInterval(start: at(-40 * 101 - 30), end: at(-40 * 101)),
    )
}
