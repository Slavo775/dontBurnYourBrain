@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// The owner's rule from card #44: a break taken with nothing running is not
// untracked time. Once it ended, by hand or by running out, the untracked
// time counts from its real end, which must be later than the usual start,
// not after now and not before today.

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

/// Where the untracked time starts at `now` with the latest break `resting`.
private func untrackedStart(
    _ desk: Desk, appStart: Date = at(-60), now: Date, after resting: IdleBreak?,
) throws -> Date {
    try MenuBarLabel.untrackedStart(in: desk.context, appStart: appStart, now: now, calendar: utc, idleBreak: resting)
}

/// A desk whose latest entry, Acme's work from 08:30, ended at nine.
private func deskWithWorkUntilNine() throws -> Desk {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-30), end: nine))
    try desk.context.save()
    return desk
}

/// A break with nothing running from `start` to `end`, in minutes after nine.
private func idleBreak(_ start: Double, _ end: Double) throws -> IdleBreak {
    try #require(IdleBreak(start: at(start), end: at(end)))
}

// MARK: - Where the untracked time starts

@Test func `a break that ended after the latest entry starts the untracked time at its end`() throws {
    let desk = try deskWithWorkUntilNine()
    #expect(try untrackedStart(desk, now: at(40), after: idleBreak(10, 25)) == at(25))
    #expect(try untrackedStart(desk, now: at(25), after: idleBreak(10, 25)) == at(25))
}

@Test func `a break that ended before the latest entry leaves the entry's end`() throws {
    let desk = try deskWithWorkUntilNine()
    #expect(try untrackedStart(desk, now: at(40), after: idleBreak(-50, -40)) == nine)
}

@Test func `a break that ends after now leaves the untracked start alone`() throws {
    let desk = try deskWithWorkUntilNine()
    #expect(try untrackedStart(desk, now: at(20), after: idleBreak(10, 25)) == nine)
}

@Test func `a break that ended yesterday leaves the start of today`() throws {
    let desk = try Desk()
    // 23:00 to 23:30 yesterday, in UTC; today began at 00:00.
    let start = try untrackedStart(desk, appStart: at(-24 * 60), now: nine, after: idleBreak(-600, -570))
    #expect(start == at(-540))
}

@Test func `a break that ended before the app started leaves the app's start, one ending after it wins`() throws {
    let desk = try Desk()
    #expect(try untrackedStart(desk, appStart: at(-30), now: nine, after: idleBreak(-40, -35)) == at(-30))
    #expect(try untrackedStart(desk, appStart: at(-30), now: nine, after: idleBreak(-20, -5)) == at(-5))
}

@Test func `with no break the untracked start is the one from the entries`() throws {
    let desk = try deskWithWorkUntilNine()
    #expect(try untrackedStart(desk, now: at(40), after: nil) == nine)
    #expect(try MenuBarLabel.untrackedStart(in: desk.context, appStart: at(-60), now: at(40), calendar: utc) == nine)
}

// MARK: - What the item shows after the break

/// What the item shows at `now` with nothing running and the latest break `resting`.
private func shown(_ desk: Desk, at now: Date, after resting: IdleBreak?) throws -> MenuBarLabel {
    let status = try desk.engine.settle(at: now)
    let since = try untrackedStart(desk, appStart: nine, now: now, after: resting)
    return MenuBarLabel(status: status, workspace: nil, untrackedSince: since, at: now)
}

@Test func `after a break ended by hand the untracked time counts from the moment it ended`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 30, at: nine)
    var resting: IdleBreak?
    try QuickAction.startBreak(minutes: 15, with: desk.engine, idleBreak: &resting, at: at(40))
    let started = try #require(resting)

    try QuickAction.breakOrEndBreak.perform(with: desk.engine, idleBreak: &resting, at: at(50))

    let finished = try #require(started.ended(at: at(50)))
    #expect(finished.end == at(50))
    #expect(try shown(desk, at: at(64), after: finished) == .idle(untracked: nil))
    #expect(try shown(desk, at: at(65), after: finished) == .idle(untracked: "0:15"))
    #expect(try shown(desk, at: at(65), after: nil) == .idle(untracked: "0:35"))
}

@Test func `after a break ran out the untracked time counts from its planned end`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 30, at: nine)
    var resting: IdleBreak?
    try QuickAction.startBreak(minutes: 15, with: desk.engine, idleBreak: &resting, at: at(40))
    let started = try #require(resting)

    let status = try desk.engine.settle(at: at(80))

    #expect(started.running(beside: status, at: at(80)) == nil)
    let finished = try #require(started.ended(at: at(80)))
    #expect(finished.end == at(55))
    #expect(try shown(desk, at: at(80), after: finished) == .idle(untracked: "0:25"))
}

@Test func `a block after the break counts from its own end again`() throws {
    let desk = try Desk()
    let finished = try idleBreak(0, 10)
    try desk.engine.start(desk.globex, minutes: 20, at: at(15))
    try desk.engine.settle(at: at(35))

    #expect(try untrackedStart(desk, now: at(60), after: finished) == at(35))
    #expect(try shown(desk, at: at(60), after: finished) == .idle(untracked: "0:25"))
}
