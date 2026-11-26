@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// When the app asks about time away and when it does not, how a waiting
// question widens, a clock that moves back, and entries of no length.

/// A desk whose Acme runs a 60-minute block from nine, with no rhythm.
private func acmeRunning() throws -> Desk {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 60, at: nine)
    return desk
}

// MARK: - The length of the time away

@Test func `the time away runs from the last input to the return`() {
    let span = away(20, 45)
    #expect(span.length == 25 * 60)
    #expect(span.minutes == 25)
}

@Test(arguments: [
    (0.0, 0), (59.4, 0), (59.5, 1), (60, 1), (119.4, 1), (119.6, 2), (25 * 60 - 0.4, 25), (25 * 60 + 59, 25),
] as [(TimeInterval, Int)])
func `the minutes away round to the nearest second, then down to whole minutes`(seconds: TimeInterval, minutes: Int) {
    #expect(TimeAway(start: nine, end: nine.addingTimeInterval(seconds)).minutes == minutes)
}

@Test func `a return before the last input, as after the clock moved back, is a time away of no length`() {
    let span = TimeAway(start: at(40), end: at(20))
    #expect(span.end == at(40))
    #expect(span.length == 0)
    #expect(span.minutes == 0)
}

@Test func `a second time away widens the question from the first start to the latest return`() {
    #expect(away(20, 30).widened(by: away(35, 50)) == away(20, 50))
    #expect(away(35, 50).widened(by: away(20, 30)) == away(20, 50))
    #expect(away(20, 50).widened(by: away(30, 40)) == away(20, 50))
}

// MARK: - When the app asks

@Test func `time away shorter than the threshold brings no question`() throws {
    let desk = try acmeRunning()
    #expect(try desk.engine.ask(since: 20, returnedAt: 29.99) == nil)
    #expect(try desk.engine.timeAway(since: at(20), returnedAt: at(21), threshold: 60) == away(20, 21))
    #expect(try desk.engine.timeAway(since: at(20), returnedAt: at(20.99), threshold: 60) == nil)
}

@Test func `time away exactly at the threshold brings the question`() throws {
    let desk = try acmeRunning()
    #expect(try desk.engine.ask(since: 20, returnedAt: 30) == away(20, 30))
}

@Test func `with nothing running there is nothing to ask`() throws {
    let desk = try Desk()
    #expect(try desk.engine.ask(since: 20, returnedAt: 40) == nil)

    try desk.engine.start(desk.acme, minutes: 60, at: nine)
    try desk.engine.end(at: at(10))
    #expect(try desk.engine.ask(since: 20, returnedAt: 40) == nil)
}

@Test func `a block paused the whole time away brings no question and keeps its pause`() throws {
    let desk = try acmeRunning()
    try desk.engine.pause(at: at(20))

    #expect(try desk.engine.ask(since: 20, returnedAt: 50) == nil)
    #expect(try pieces(desk.context) == [work(0, 20)])
    #expect(try desk.engine.settle(at: at(50)).state == .paused)
}

@Test func `a break lasting the whole time away brings no question`() throws {
    let desk = try acmeRunning()
    try desk.engine.startBreak(minutes: 30, at: at(20))

    #expect(try desk.engine.ask(since: 20, returnedAt: 45) == nil)
    #expect(try pieces(desk.context) == [work(0, 20), Piece(kind: .break, start: at(20), end: nil)])
}

@Test func `a break that ran out too shortly before the return brings no question`() throws {
    let desk = try acmeRunning()
    try desk.engine.startBreak(minutes: 15, at: at(20))

    // Away for 25 minutes, but the block counted only the last 9 as work.
    #expect(try desk.engine.ask(since: 20, returnedAt: 44) == nil)
    #expect(try desk.engine.ask(since: 20, returnedAt: 45) == away(35, 45))
}

@Test func `a rhythm that waits after a break leaves the block paused, so nothing is asked`() throws {
    let desk = try Desk()
    try desk.acmeFollows(waitingPreset())
    try desk.engine.start(desk.acme, minutes: 60, at: nine)
    try desk.engine.startBreak(minutes: 5, at: at(10))

    #expect(try desk.engine.ask(since: 10, returnedAt: 40) == nil)
    #expect(try desk.engine.settle(at: at(40)).state == .paused)
}

@Test func `a manual entry is never time away the app asks about`() throws {
    let desk = try Desk()
    let manual = TimeEntry(workspace: desk.acme, start: nine, end: at(60), source: .manual)
    desk.context.insert(manual)
    try desk.context.save()

    #expect(try desk.engine.ask(since: 20, returnedAt: 40) == nil)
}

@Test func `a work entry outside any block is never time away the app asks about`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.acme, start: nine, end: at(60)))
    try desk.context.save()

    #expect(try desk.engine.ask(since: 20, returnedAt: 40) == nil)
}

// MARK: - A waiting question

@Test(arguments: [
    Outcome(.meeting, [work(0, 20), meeting(20, 50), work(50, nil)], endsAt: 60),
    Outcome(.discard, [work(0, 20), work(50, nil)], endsAt: 90),
])
func `an answer to a widened question covers both times away and the work between them`(outcome: Outcome) throws {
    let desk = try acmeRunning()
    let first = try #require(try desk.engine.ask(since: 20, returnedAt: 30))
    let second = try #require(try desk.engine.ask(since: 35, returnedAt: 50))

    try desk.engine.settle(first.widened(by: second), as: outcome.answer, at: at(51))

    #expect(try pieces(desk.context) == outcome.pieces)
    #expect(try desk.engine.settle(at: at(51)).plannedEnd == at(outcome.end))
    try expectHistoryKeepsRules(desk.context)
}

/// Not Work: the time away stays work then, which a later answer may still change.
@Test(arguments: [AwayAnswer.meeting, .break, .discard])
func `a second answer to the same time away changes nothing more`(answer: AwayAnswer) throws {
    let desk = try acmeRunning()
    let span = try #require(try desk.engine.ask(since: 20, returnedAt: 40))
    try desk.engine.settle(span, as: answer, at: at(41))
    let once = try pieces(desk.context)

    try desk.engine.settle(span, as: answer, at: at(42))
    try desk.engine.settle(span, as: .discard, at: at(43))

    #expect(try pieces(desk.context) == once)
    try expectHistoryKeepsRules(desk.context)
}

@Test(arguments: [AwayAnswer.meeting, .break, .discard])
func `an answer about time away no work entry counts any more changes nothing`(answer: AwayAnswer) throws {
    let desk = try acmeRunning()
    let span = try #require(try desk.engine.ask(since: 20, returnedAt: 40))
    // He ended the block in the window before the time away, after the question came.
    let entry = try #require(try entries(desk.context).first)
    entry.end = at(15)
    try desk.engine.end(at: at(41))
    let before = try pieces(desk.context)

    try desk.engine.settle(span, as: answer, at: at(42))

    #expect(try pieces(desk.context) == before)
}

// MARK: - A clock that moved back

@Test(arguments: [
    (AwayAnswer.meeting, [work(0, 20), meeting(20, 40), work(40, nil)]),
    (.break, [work(0, 20), breakPiece(20, 40), work(40, nil)]),
    (.discard, [work(0, 20), work(40, nil)]),
] as [(AwayAnswer, [Piece])])
func `an answer given before the return is taken at the return`(answer: AwayAnswer, expected: [Piece]) throws {
    let desk = try acmeRunning()
    let span = try #require(try desk.engine.ask(since: 20, returnedAt: 40))

    try desk.engine.settle(span, as: answer, at: at(30))

    #expect(try pieces(desk.context) == expected)
    try expectHistoryKeepsRules(desk.context)
}

@Test func `a return reported before the last input brings no question`() throws {
    let desk = try acmeRunning()
    #expect(try desk.engine.ask(since: 40, returnedAt: 20) == nil)
    #expect(try pieces(desk.context) == [work(0, nil)])
}

// MARK: - Entries of no length

@Test(arguments: [
    (AwayAnswer.meeting, [work(0, 40), meeting(40, 60)]),
    (.break, [work(0, 40), breakPiece(40, 60)]),
    (.discard, [work(0, 40)]),
] as [(AwayAnswer, [Piece])])
func `a return exactly at the block's end leaves no work entry of no length`(
    answer: AwayAnswer, expected: [Piece],
) throws {
    let desk = try acmeRunning()
    let span = try #require(try desk.engine.ask(since: 40, returnedAt: 60))

    try desk.engine.settle(span, as: answer, at: at(60))

    #expect(try pieces(desk.context) == expected)
    try expectHistoryKeepsRules(desk.context)
}

@Test func `time away from the block's very start reuses the work entry rather than leave one of no length`() throws {
    let desk = try acmeRunning()
    let span = try #require(try desk.engine.ask(since: -5, returnedAt: 20))
    #expect(span == away(0, 20))

    try desk.engine.settle(span, as: .meeting, at: at(21))

    #expect(try pieces(desk.context) == [meeting(0, 20), work(20, nil)])
    #expect(try entries(desk.context).count == 2)
    try expectHistoryKeepsRules(desk.context)
}

@Test func `discarding time away from the block's very start moves the whole block later`() throws {
    let desk = try acmeRunning()
    let span = try #require(try desk.engine.ask(since: 0, returnedAt: 20))

    try desk.engine.settle(span, as: .discard, at: at(21))

    #expect(try pieces(desk.context) == [work(20, nil)])
    #expect(try desk.engine.settle(at: at(21)).plannedEnd == at(80))
    try expectHistoryKeepsRules(desk.context)
}
