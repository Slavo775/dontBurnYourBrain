@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// The card's done-when intervals, driven the way the panel, its keys and the
// right-click menu drive them.

/// A stored entry, its times in minutes after nine.
private struct Span {
    let kind: TimeEntryKind
    let start: Double
    let end: Double?
}

/// Every stored entry as a ``Span``, earliest first.
private func intervals(_ context: ModelContext) throws -> [Span] {
    try entries(context).map { entry in
        Span(
            kind: entry.kind,
            start: entry.start.timeIntervalSince(nine) / 60,
            end: entry.end.map { $0.timeIntervalSince(nine) / 60 },
        )
    }
}

@Test func `every quick action is unavailable while nothing runs`() {
    for action in QuickAction.allCases {
        #expect(!action.isAvailable(in: .idle))
    }
}

@Test func `break is the only quick action unavailable while paused`() {
    #expect(QuickAction.pauseOrResume.isAvailable(in: .paused))
    #expect(!QuickAction.breakOrEndBreak.isAvailable(in: .paused))
    #expect(QuickAction.extend.isAvailable(in: .paused))
}

@Test func `every quick action is available while working and on a break`() {
    for action in QuickAction.allCases {
        #expect(action.isAvailable(in: .working))
        #expect(action.isAvailable(in: .onBreak))
    }
}

@Test func `pause then resume leaves two work entries with a gap, and the block ends later by the gap`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    try QuickAction.pauseOrResume.perform(with: desk.engine, at: at(10))
    #expect(try desk.engine.settle(at: at(12)).state == .paused)
    try QuickAction.pauseOrResume.perform(with: desk.engine, at: at(15))

    let all = try intervals(desk.context)
    #expect(all.count == 2)
    #expect(all.map(\.kind) == [.work, .work])
    #expect(all.map(\.start) == [0, 15])
    #expect(all.map(\.end) == [10, nil])
    let status = try desk.engine.settle(at: at(20))
    #expect(status.state == .working)
    #expect(status.plannedEnd == at(65))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `break then end break leaves a break between two work entries, and the block's end does not move`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    try QuickAction.breakOrEndBreak.perform(with: desk.engine, at: at(10))
    #expect(try desk.engine.settle(at: at(11)).state == .onBreak)
    try QuickAction.breakOrEndBreak.perform(with: desk.engine, at: at(13))

    let all = try intervals(desk.context)
    #expect(all.map(\.kind) == [.work, .break, .work])
    #expect(all.map(\.start) == [0, 10, 13])
    #expect(all.map(\.end) == [10, 13, nil])
    #expect(try desk.engine.settle(at: at(20)).plannedEnd == at(60))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `extend adds a quarter of an hour to the block`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    try QuickAction.extend.perform(with: desk.engine, at: at(10))

    #expect(try blocks(desk.context).first?.plannedMinutes == 75)
    #expect(try desk.engine.settle(at: at(10)).plannedEnd == at(75))
}

@Test func `the +15 action works while paused and on a break`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try QuickAction.pauseOrResume.perform(with: desk.engine, at: at(10))
    try QuickAction.extend.perform(with: desk.engine, at: at(11))
    try QuickAction.pauseOrResume.perform(with: desk.engine, at: at(12))
    try QuickAction.breakOrEndBreak.perform(with: desk.engine, at: at(20))
    try QuickAction.extend.perform(with: desk.engine, at: at(21))

    #expect(try blocks(desk.context).first?.plannedMinutes == 90)
}

@Test func `pause on a break ends the break and leaves the block paused`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try QuickAction.breakOrEndBreak.perform(with: desk.engine, at: at(10))

    try QuickAction.pauseOrResume.perform(with: desk.engine, at: at(12))

    #expect(try desk.engine.settle(at: at(13)).state == .paused)
    let all = try intervals(desk.context)
    #expect(all.map(\.kind) == [.work, .break])
    #expect(all.map(\.end) == [10, 12])
}

@Test func `break while paused is refused and changes nothing`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try QuickAction.pauseOrResume.perform(with: desk.engine, at: at(10))

    #expect(throws: TimerEngineError.notAllowed(.paused)) {
        try QuickAction.breakOrEndBreak.perform(with: desk.engine, at: at(12))
    }

    let all = try intervals(desk.context)
    #expect(all.count == 1)
    #expect(all.first?.end == 10)
    #expect(try desk.engine.settle(at: at(12)).state == .paused)
}

@Test func `a quick action while nothing runs is refused`() throws {
    let desk = try Desk()
    for action in QuickAction.allCases {
        #expect(throws: TimerEngineError.notAllowed(.idle)) {
            try action.perform(with: desk.engine, at: nine)
        }
    }
    #expect(try entries(desk.context).isEmpty)
}

@Test func `switch ends the block and starts the chosen workspace at its default length`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: nine)

    try desk.engine.switchTo(desk.globex, at: at(20))

    let all = try blocks(desk.context)
    #expect(all.count == 2)
    #expect(all[0].workspace === desk.acme)
    #expect(all[0].state == .done)
    #expect(all[1].workspace === desk.globex)
    #expect(all[1].state == .running)
    #expect(all[1].plannedStart == at(20))
    #expect(all[1].plannedMinutes == 45)
    let spans = try intervals(desk.context)
    #expect(spans.map(\.start) == [0, 20])
    #expect(spans.map(\.end) == [20, nil])
    #expect(try desk.engine.runningBlock() === all[1])
    #expect(try desk.engine.settle(at: at(20)).plannedEnd == at(65))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `switch from a pause starts the new block where the switch happens`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try QuickAction.pauseOrResume.perform(with: desk.engine, at: at(10))

    try desk.engine.switchTo(desk.personal, at: at(30))

    let block = try #require(try desk.engine.runningBlock())
    #expect(block.workspace === desk.personal)
    #expect(block.plannedStart == at(30))
    #expect(block.plannedMinutes == 25)
    try expectHistoryKeepsRules(desk.context)
}

@Test func `end block ends the block early, and the entry ends at that moment`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    try desk.engine.end(at: at(25))

    let block = try #require(try blocks(desk.context).first)
    #expect(block.state == .done)
    let all = try intervals(desk.context)
    #expect(all.count == 1)
    #expect(all.first?.end == 25)
    #expect(try desk.engine.settle(at: at(26)) == .idle)
    #expect(try desk.engine.runningBlock() == nil)
}

@Test func `end block on a break ends the break at that moment`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try QuickAction.breakOrEndBreak.perform(with: desk.engine, at: at(10))

    try desk.engine.end(at: at(12))

    let all = try intervals(desk.context)
    #expect(all.map(\.kind) == [.work, .break])
    #expect(all.map(\.end) == [10, 12])
    #expect(try desk.engine.settle(at: at(12)) == .idle)
}
