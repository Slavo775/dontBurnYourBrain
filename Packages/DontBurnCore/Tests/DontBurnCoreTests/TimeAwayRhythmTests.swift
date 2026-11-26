@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// How a block's rhythm reads the entries an answer about time away leaves.
// Acme follows the seeded 25/5 and runs a two-hour block from nine. He is
// away from 09:20 to 09:40, so the first break came due at 09:25 while he was away.

/// The rhythm at 09:41 after answering `answer` about the time away from `start` to `end` minutes after nine.
private func rhythm(after answer: AwayAnswer, awayFrom start: Double = 20, to end: Double = 40) throws -> FocusRhythm {
    let desk = try runningOn25(minutes: 120)
    let span = try #require(try desk.engine.ask(since: start, returnedAt: end))
    try desk.engine.settle(span, as: answer, at: at(end))
    return try checkedRhythm(desk.engine, at: at(end + 1))
}

@Test func `after Work the rhythm reads the time away as focus and skips the break that came due`() throws {
    let read = try rhythm(after: .work)

    #expect(read.current == focus(30, 55))
    #expect(!read.isBreakDue)
    #expect(read.roundsDone == 1)
    #expect(read.nextBreak == shortBreak(55, 60))
}

@Test func `after Meeting the rhythm reads as after Work, since a meeting is focus`() throws {
    #expect(try rhythm(after: .meeting) == rhythm(after: .work))
}

@Test func `after Break the time away ends the round as a break taken by hand, and a full focus follows`() throws {
    let read = try rhythm(after: .break)

    #expect(read.current == focus(40, 65))
    #expect(!read.isBreakDue)
    #expect(read.roundsDone == 1)
    #expect(read.nextBreak == shortBreak(65, 70))
}

@Test func `after Discard the time away is a pause, so the focus interval keeps the work it had left`() throws {
    let read = try rhythm(after: .discard)

    #expect(read.current == focus(0, 45))
    #expect(!read.isBreakDue)
    #expect(read.roundsDone == 0)
    #expect(read.nextBreak == shortBreak(45, 50))
    #expect(read.plan.last?.end == at(140))
}

@Test func `after Discard a break that was due when he left is still due, with the time it had left`() throws {
    // Away from 09:27, two minutes into the break that came due at 09:25.
    let read = try rhythm(after: .discard, awayFrom: 27, to: 47)

    #expect(read.isBreakDue)
    #expect(read.current == shortBreak(25, 50))
    #expect(read.roundsDone == 1)
}
