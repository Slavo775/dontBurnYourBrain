@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// Each answer to the question about time away, for time away in the middle of
// a block, across its planned end, after it ran out, and around breaks that ran
// out while he was away. Acme's block runs 60 minutes from nine unless a test
// says otherwise, so it is planned to end at 10:00.

/// A desk whose Acme runs a block of `minutes` from nine, with no rhythm.
private func acmeRunning(minutes: Int = 60) throws -> Desk {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: minutes, at: nine)
    return desk
}

// MARK: - In the middle of a block

@Test(arguments: [
    Outcome(.work, [work(0, nil)], endsAt: 60),
    Outcome(.meeting, [work(0, 20), meeting(20, 40), work(40, nil)], endsAt: 60),
    Outcome(.break, [work(0, 20), breakPiece(20, 40), work(40, nil)], endsAt: 60),
    Outcome(.discard, [work(0, 20), work(40, nil)], endsAt: 80),
], Absence.allCases)
func `an answer about time away in the middle of a block leaves the entries it says`(
    outcome: Outcome, absence: Absence,
) throws {
    let desk = try acmeRunning()
    let away = try askedAway(desk, since: 20, returnedAt: 40, by: absence)

    try desk.engine.settle(away, as: outcome.answer, at: at(41))

    #expect(away == TimeAway(start: at(20), end: at(40)))
    #expect(try pieces(desk.context) == outcome.pieces)
    let status = try desk.engine.settle(at: at(41))
    #expect(status.state == .working)
    #expect(status.plannedEnd == at(outcome.end))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `asking changes nothing, so the block goes on as before until he answers`() throws {
    let desk = try acmeRunning()
    _ = try desk.engine.ask(since: 20, returnedAt: 40)

    #expect(try pieces(desk.context) == [work(0, nil)])
    #expect(try desk.engine.settle(at: at(41)).plannedEnd == at(60))
}

// MARK: - Across the block's planned end

@Test(arguments: [
    (AwayAnswer.work, [work(0, 60)]),
    (.meeting, [work(0, 50), meeting(50, 60)]),
    (.break, [work(0, 50), breakPiece(50, 60)]),
    (.discard, [work(0, 50)]),
] as [(AwayAnswer, [Piece])], Absence.allCases)
func `an answer about time away across the planned end keeps the block ended there or where he left`(
    outcome: (answer: AwayAnswer, pieces: [Piece]), absence: Absence,
) throws {
    let desk = try acmeRunning()
    let away = try askedAway(desk, since: 50, returnedAt: 80, by: absence)

    try desk.engine.settle(away, as: outcome.answer, at: at(81))

    #expect(away == TimeAway(start: at(50), end: at(80)))
    #expect(try pieces(desk.context) == outcome.pieces)
    #expect(try desk.engine.settle(at: at(81)) == .idle)
    #expect(try blocks(desk.context).map(\.state) == [.done])
    try expectHistoryKeepsRules(desk.context)
}

@Test func `a sleep overnight across the planned end asks about the whole night`() throws {
    let desk = try acmeRunning()
    // Last input at 09:50, the Mac sleeps, and he wakes it at 08:00 the next day.
    let away = try askedAway(desk, since: 50, returnedAt: 23 * 60, by: .sleep)

    try desk.engine.settle(away, as: .discard, at: at(23 * 60))

    #expect(away.minutes == 23 * 60 - 50)
    #expect(try pieces(desk.context) == [work(0, 50)])
    try expectHistoryKeepsRules(desk.context)
}

// MARK: - The block ran out after the return, before the answer

@Test(arguments: [
    (AwayAnswer.work, [work(0, 60)]),
    (.meeting, [work(0, 30), meeting(30, 50), work(50, 60)]),
    (.break, [work(0, 30), breakPiece(30, 50), work(50, 60)]),
    (.discard, [work(0, 30), work(50, 60)]),
] as [(AwayAnswer, [Piece])])
func `an answer after the block ran out leaves it ended at its planned end`(
    answer: AwayAnswer, expected: [Piece],
) throws {
    let desk = try acmeRunning()
    let away = try askedAway(desk, since: 30, returnedAt: 50, by: .idle)
    try desk.engine.tick(from: 50, to: 70)

    try desk.engine.settle(away, as: answer, at: at(70))

    #expect(try pieces(desk.context) == expected)
    #expect(try desk.engine.settle(at: at(70)) == .idle)
    try expectHistoryKeepsRules(desk.context)
}

// MARK: - A break ran out while he was away

@Test(arguments: [
    Outcome(.work, [work(0, 10), breakPiece(10, 15), work(15, nil)], endsAt: 60),
    Outcome(.meeting, [work(0, 10), breakPiece(10, 15), meeting(15, 40), work(40, nil)], endsAt: 60),
    // Two breaks side by side, which the rhythm counts as two rounds: a known limit.
    Outcome(.break, [work(0, 10), breakPiece(10, 15), breakPiece(15, 40), work(40, nil)], endsAt: 60),
    Outcome(.discard, [work(0, 10), breakPiece(10, 15), work(40, nil)], endsAt: 85),
], Absence.allCases)
func `an answer after a break ran out while he was away starts the time away where work went on`(
    outcome: Outcome, absence: Absence,
) throws {
    let desk = try acmeRunning()
    try desk.engine.startBreak(minutes: 5, at: at(10))
    let away = try askedAway(desk, since: 10, returnedAt: 40, by: absence)

    try desk.engine.settle(away, as: outcome.answer, at: at(41))

    #expect(away == TimeAway(start: at(15), end: at(40)))
    #expect(try pieces(desk.context) == outcome.pieces)
    #expect(try desk.engine.settle(at: at(41)).plannedEnd == at(outcome.end))
    try expectHistoryKeepsRules(desk.context)
}

@Test(arguments: [
    (AwayAnswer.work, [work(0, 20), breakPiece(20, 25), work(25, 30)]),
    (.meeting, [work(0, 20), breakPiece(20, 25), meeting(25, 30)]),
    (.break, [work(0, 20), breakPiece(20, 25), breakPiece(25, 30)]),
    // The work entry is all time away, so it goes, and the block ends where the time away began.
    (.discard, [work(0, 20), breakPiece(20, 25)]),
] as [(AwayAnswer, [Piece])], Absence.allCases)
func `an answer after a break and the block both ran out while he was away`(
    outcome: (answer: AwayAnswer, pieces: [Piece]), absence: Absence,
) throws {
    let desk = try acmeRunning(minutes: 30)
    try desk.engine.startBreak(minutes: 5, at: at(20))
    let away = try askedAway(desk, since: 20, returnedAt: 60, by: absence)

    try desk.engine.settle(away, as: outcome.answer, at: at(61))

    #expect(away == TimeAway(start: at(25), end: at(60)))
    #expect(try pieces(desk.context) == outcome.pieces)
    #expect(try desk.engine.settle(at: at(61)) == .idle)
    try expectHistoryKeepsRules(desk.context)
}

// MARK: - What the new entries carry

@Test(arguments: [AwayAnswer.meeting, .break, .discard])
func `the entries an answer leaves keep the block's workspace, project and source`(answer: AwayAnswer) throws {
    let desk = try Desk()
    let website = Project(name: "Website", workspace: desk.acme)
    desk.context.insert(website)
    try desk.engine.start(desk.acme, minutes: 60, project: website, at: nine)
    let away = try #require(try desk.engine.ask(since: 20, returnedAt: 40))

    try desk.engine.settle(away, as: answer, at: at(41))

    let block = try #require(try blocks(desk.context).first)
    for entry in try entries(desk.context) {
        #expect(entry.block === block)
        #expect(entry.workspace === desk.acme)
        #expect(entry.project === website)
        #expect(entry.source == .timer)
    }
}

@Test func `a discard after +15 moves the extended end later by the time away`() throws {
    let desk = try acmeRunning()
    let away = try #require(try desk.engine.ask(since: 20, returnedAt: 40))
    try desk.engine.extend(at: at(41))

    try desk.engine.settle(away, as: .discard, at: at(42))

    #expect(try desk.engine.settle(at: at(42)).plannedEnd == at(95))
    try expectHistoryKeepsRules(desk.context)
}
