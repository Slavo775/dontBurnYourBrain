@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// The last input before a time away is often the click that took an action,
// such as Pause or Break, and the action ends the work entry a moment later.
// A work entry that ended within `TimeAway.inputSlack` after the last input
// did not run while he was away. The Mac sleeps right after the click here,
// so nothing settles until he wakes it.

/// The instant `seconds` after `minutes` after nine.
private func at(_ minutes: Double, plus seconds: TimeInterval) -> Date {
    at(minutes).addingTimeInterval(seconds)
}

/// How long after the click its action ends the work entry, in seconds.
private let click: TimeInterval = 0.05

/// A desk whose Acme runs a two-hour block from nine, with no rhythm.
private func acmeRunning() throws -> Desk {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: nine)
    return desk
}

@Test func `a sleep right after a click on Pause asks nothing and leaves the pause alone`() throws {
    let desk = try acmeRunning()
    try desk.engine.pause(at: at(20, plus: click))

    #expect(try desk.engine.ask(since: 20, returnedAt: 80) == nil)
    #expect(try pieces(desk.context) == [Piece(kind: .work, start: nine, end: at(20, plus: click))])
    #expect(try desk.engine.settle(at: at(80)).state == .paused)
}

@Test func `a sleep right after a click on Break that outlasts the sleep asks nothing`() throws {
    let desk = try acmeRunning()
    try desk.engine.startBreak(minutes: 60, at: at(20, plus: click))

    #expect(try desk.engine.ask(since: 20, returnedAt: 50) == nil)
    #expect(try desk.engine.settle(at: at(50)).state == .onBreak)
}

@Test func `a break that waits for Resume after a click on Break asks nothing when it runs out in the sleep`() throws {
    let desk = try Desk()
    try desk.acmeFollows(waitingPreset())
    try desk.engine.start(desk.acme, minutes: 120, at: nine)
    try desk.engine.startBreak(minutes: 5, at: at(20, plus: click))

    #expect(try desk.engine.ask(since: 20, returnedAt: 80) == nil)
    #expect(try desk.engine.settle(at: at(80)).state == .paused)
}

// MARK: - Lunch: a break that runs out during the sleep

@Test func `a break that runs out during the sleep asks about the time from the break's end`() throws {
    let desk = try acmeRunning()
    try desk.engine.startBreak(minutes: 30, at: at(20, plus: click))

    let away = try #require(try desk.engine.ask(since: 20, returnedAt: 80))

    #expect(away == TimeAway(start: at(50, plus: click), end: at(80)))
    #expect(away.minutes == 30)
}

@Test(arguments: [
    (AwayAnswer.work, [
        Piece(kind: .work, start: nine, end: at(20, plus: click)),
        Piece(kind: .break, start: at(20, plus: click), end: at(50, plus: click)),
        Piece(kind: .work, start: at(50, plus: click), end: nil),
    ]),
    (.meeting, [
        Piece(kind: .work, start: nine, end: at(20, plus: click)),
        Piece(kind: .break, start: at(20, plus: click), end: at(50, plus: click)),
        Piece(kind: .meeting, start: at(50, plus: click), end: at(80)),
        work(80, nil),
    ]),
    (.discard, [
        Piece(kind: .work, start: nine, end: at(20, plus: click)),
        Piece(kind: .break, start: at(20, plus: click), end: at(50, plus: click)),
        work(80, nil),
    ]),
] as [(AwayAnswer, [Piece])])
func `an answer about lunch changes only the time after the break's end`(answer: AwayAnswer, expected: [Piece]) throws {
    let desk = try acmeRunning()
    try desk.engine.startBreak(minutes: 30, at: at(20, plus: click))
    let away = try #require(try desk.engine.ask(since: 20, returnedAt: 80))

    try desk.engine.settle(away, as: answer, at: at(81))

    #expect(try pieces(desk.context) == expected)
    try expectHistoryKeepsRules(desk.context)
}

@Test func `discarding lunch moves the block's end later by the time after the break's end`() throws {
    let desk = try acmeRunning()
    try desk.engine.startBreak(minutes: 30, at: at(20, plus: click))
    let away = try #require(try desk.engine.ask(since: 20, returnedAt: 80))

    try desk.engine.settle(away, as: .discard, at: at(81))

    #expect(try desk.engine.settle(at: at(81)).plannedEnd == at(150, plus: -click))
}

// MARK: - The edge of the slack

@Test func `a work entry that ended exactly one second after the last input does not count`() throws {
    let desk = try acmeRunning()
    try desk.engine.pause(at: at(20, plus: TimeAway.inputSlack))

    #expect(try desk.engine.ask(since: 20, returnedAt: 80) == nil)
}

@Test func `a work entry that ended later than the slack still counts, from the last input`() throws {
    let desk = try acmeRunning()
    try desk.engine.pause(at: at(20, plus: 1.5))

    #expect(try desk.engine.ask(since: 20, returnedAt: 80) == away(20, 80))
}

@Test func `a block that runs out seconds after the last input asks across its end, and Discard ends it`() throws {
    let desk = try Desk()
    // The block ends at 10:00, two seconds after the last input, and the Mac sleeps until 11:00.
    try desk.engine.start(desk.acme, minutes: 60, at: nine)
    let away = try #require(try desk.engine.timeAway(
        since: at(60, plus: -2), returnedAt: at(120), threshold: tenMinutes,
    ))

    try desk.engine.settle(away, as: .discard, at: at(120))

    #expect(away == TimeAway(start: at(60, plus: -2), end: at(120)))
    #expect(try pieces(desk.context) == [Piece(kind: .work, start: nine, end: at(60, plus: -2))])
}

@Test func `a running work entry always counts, even one that started just before the last input`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: at(20, plus: -0.5))

    #expect(try desk.engine.ask(since: 20, returnedAt: 40) == TimeAway(start: at(20), end: at(40)))
}
