@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// Card #44 inside a block: a break of a chosen length, and +15 during it,
// which lengthens the break and the block alike.

/// The open entry of the running block, which the engine keeps.
private func openEntry(_ context: ModelContext) throws -> TimeEntry {
    try #require(try entries(context).first { $0.end == nil })
}

// MARK: - The lengths offered

@Test func `the break lengths offered are 5, 15, 30 and 60 minutes, and the default is the shortest`() {
    #expect(TimerEngine.breakLengthChoices == [5, 15, 30, 60])
    #expect(TimerEngine.breakLengthChoices.first == TimerEngine.defaultBreakMinutes)
}

@Test(arguments: [
    (5, 5), (15, 15), (30, 30), (60, 60),
    (0, 5), (-5, 5), (7, 5), (10, 5), (45, 5), (61, 5), (Int.max, 5), (Int.min, 5),
] as [(Int, Int)])
func `a remembered break length is kept only when it is one of the four, otherwise it is five minutes`(
    remembered: Int, length: Int,
) {
    #expect(TimerEngine.breakLength(remembered: remembered) == length)
}

@Test(arguments: [
    (1, 5), (2, 15), (3, 30), (4, 60),
    (0, nil), (5, nil), (9, nil), (-1, nil), (Int.max, nil), (Int.min, nil),
] as [(Int, Int?)])
func `the keys 1 to 4 give the four lengths and no other number gives one`(key: Int, length: Int?) {
    #expect(TimerEngine.breakLength(onKey: key) == length)
}

// MARK: - The timer's states

@Test(arguments: [
    (TimerState.idle, false, false), (.working, true, false), (.paused, true, false),
    (.onBreak, true, true), (.idleBreak, false, true),
])
func `a block runs while working, paused or on a break in it, and a break counts down in a block or with none`(
    state: TimerState, hasBlock: Bool, isBreak: Bool,
) {
    #expect(state.hasBlock == hasBlock)
    #expect(state.isBreak == isBreak)
}

@Test(arguments: TimerState.allCases)
func `a break of a chosen length can start only while working or while nothing runs`(state: TimerState) {
    #expect(QuickAction.canStartBreak(in: state) == (state == .working || state == .idle))
}

// MARK: - Starting a break of a chosen length in a block

@Test(arguments: TimerEngine.breakLengthChoices)
func `a chosen break while working is one break entry of that length, and the block's end does not move`(
    minutes: Int,
) throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: nine)
    var idleBreak: IdleBreak?

    try QuickAction.startBreak(minutes: minutes, with: desk.engine, idleBreak: &idleBreak, at: at(10))

    #expect(idleBreak == nil)
    let all = try entries(desk.context)
    #expect(all.map(\.kind) == [.work, .break])
    #expect(all[1].start == at(10))
    #expect(all[1].plannedMinutes == minutes)
    #expect(try desk.engine.settle(at: at(10)) == TimerStatus(
        state: .onBreak, plannedEnd: at(120), blockTimeLeft: 110 * 60, breakTimeLeft: Double(minutes) * 60,
    ))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `a chosen break while working drops a leftover break with nothing running`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    var idleBreak = IdleBreak(start: at(5), end: at(35))

    try QuickAction.startBreak(minutes: 15, with: desk.engine, idleBreak: &idleBreak, at: at(10))

    #expect(idleBreak == nil)
    #expect(try entries(desk.context).map(\.kind) == [.work, .break])
}

@Test func `a chosen break while paused or on a break is refused and changes nothing`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    var idleBreak: IdleBreak?
    try desk.engine.startBreak(minutes: 5, at: at(10))

    #expect(throws: TimerEngineError.notAllowed(.onBreak)) {
        try QuickAction.startBreak(minutes: 15, with: desk.engine, idleBreak: &idleBreak, at: at(11))
    }
    try desk.engine.pause(at: at(12))
    #expect(throws: TimerEngineError.notAllowed(.paused)) {
        try QuickAction.startBreak(minutes: 15, with: desk.engine, idleBreak: &idleBreak, at: at(13))
    }

    #expect(idleBreak == nil)
    let all = try entries(desk.context)
    #expect(all.map(\.kind) == [.work, .break])
    #expect(all.map(\.plannedMinutes) == [nil, 5])
    #expect(try desk.engine.settle(at: at(13)).state == .paused)
}

@Test(arguments: [0, -5, Int.min])
func `a chosen break of zero minutes or less is refused before anything changes`(minutes: Int) throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    var idleBreak: IdleBreak?

    #expect(throws: TimerEngineError.invalidMinutes) {
        try QuickAction.startBreak(minutes: minutes, with: desk.engine, idleBreak: &idleBreak, at: at(10))
    }

    #expect(try entries(desk.context).map(\.kind) == [.work])
    #expect(try desk.engine.settle(at: at(10)).state == .working)
}

// MARK: - +15 on a break in a block

@Test func `+15 on a break adds to the break and the block, so the work left after the break stays the same`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 15, at: at(10))
    let before = try desk.engine.settle(at: at(12))

    try QuickAction.extend.perform(with: desk.engine, at: at(12))

    let after = try desk.engine.settle(at: at(12))
    #expect(before == TimerStatus(state: .onBreak, plannedEnd: at(60), blockTimeLeft: 48 * 60, breakTimeLeft: 13 * 60))
    #expect(after == TimerStatus(state: .onBreak, plannedEnd: at(75), blockTimeLeft: 63 * 60, breakTimeLeft: 28 * 60))
    let workAfterBreak = { (status: TimerStatus) in (status.blockTimeLeft ?? 0) - (status.breakTimeLeft ?? 0) }
    #expect(workAfterBreak(after) == workAfterBreak(before))
    #expect(try blocks(desk.context).first?.plannedMinutes == 75)
    #expect(try openEntry(desk.context).plannedMinutes == 30)
}

@Test func `a break lengthened by +15 ends by itself at its new length, as one break entry, and work goes on`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 5, at: at(10))
    try desk.engine.extend(at: at(11))

    #expect(try desk.engine.settle(at: at(16)).state == .onBreak)
    let status = try desk.engine.settle(at: at(30.5))

    #expect(status == TimerStatus(state: .working, plannedEnd: at(75), blockTimeLeft: 44.5 * 60, breakTimeLeft: nil))
    let all = try entries(desk.context)
    #expect(all.map(\.kind) == [.work, .break, .work])
    #expect(all[1].start == at(10))
    #expect(all[1].end == at(30))
    #expect(all[1].plannedMinutes == 20)
    #expect(all[2].start == at(30))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `+15 on a break clipped at the block's end moves its countdown by fifteen minutes too`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 15, at: at(50))
    #expect(try desk.engine.settle(at: at(52)).breakTimeLeft == 8 * 60)

    try desk.engine.extend(at: at(52))

    let status = try desk.engine.settle(at: at(52))
    #expect(status.breakTimeLeft == TimeInterval(23 * 60))
    #expect(status.plannedEnd == at(75))
    #expect(try openEntry(desk.context).plannedMinutes == 30)
}

@Test func `a break still clipped after +15 ends with the block at its new end`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 15, at: at(50))
    try desk.engine.extend(at: at(52))

    #expect(try desk.engine.settle(at: at(74)).state == .onBreak)
    #expect(try desk.engine.settle(at: at(76)) == .idle)

    let all = try entries(desk.context)
    #expect(all.map(\.kind) == [.work, .break])
    #expect(all[1].end == at(75))
    #expect(try blocks(desk.context).first?.state == .done)
    try expectHistoryKeepsRules(desk.context)
}

@Test func `+15 on a break without a planned length adds to the block alone`() throws {
    let desk = try Desk()
    let block = TimeBlock(workspace: desk.acme, plannedStart: nine, plannedMinutes: 60, state: .running)
    desk.context.insert(block)
    desk.context.insert(TimeEntry(workspace: desk.acme, start: nine, end: nil, kind: .break, block: block))

    try desk.engine.extend(at: at(10))

    let status = try desk.engine.settle(at: at(10))
    #expect(status.state == .onBreak)
    #expect(status.breakTimeLeft == nil)
    #expect(status.plannedEnd == at(75))
    #expect(try openEntry(desk.context).plannedMinutes == nil)
}

@Test func `+15 while working or paused leaves an earlier break's length alone`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 5, at: at(10))
    try desk.engine.endBreak(at: at(12))
    try desk.engine.extend(at: at(20))
    try desk.engine.startBreak(minutes: 15, at: at(30))
    try desk.engine.pause(at: at(32))
    try desk.engine.extend(at: at(33))

    #expect(try entries(desk.context).map(\.plannedMinutes) == [nil, 5, nil, 15])
    #expect(try blocks(desk.context).first?.plannedMinutes == 90)
}

@Test func `+15 that would overflow the break's length is refused and changes neither length`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: Int.max - 5, at: at(10))

    #expect(throws: TimerEngineError.invalidMinutes) { try desk.engine.extend(at: at(11)) }

    #expect(try openEntry(desk.context).plannedMinutes == Int.max - 5)
    #expect(try blocks(desk.context).first?.plannedMinutes == 60)
    #expect(try desk.engine.settle(at: at(11)).plannedEnd == at(60))
}
