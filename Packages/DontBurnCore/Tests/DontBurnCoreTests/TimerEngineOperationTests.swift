@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// One test or more per row of the card's effect table.

@Test func `start begins a block of the given length with a running work entry`() throws {
    let desk = try Desk()

    try desk.engine.start(desk.acme, minutes: 90, at: nine)

    let block = try #require(try blocks(desk.context).first)
    #expect(block.state == .running)
    #expect(block.workspace === desk.acme)
    #expect(block.plannedStart == nine)
    #expect(block.plannedMinutes == 90)
    let entry = try #require(try entries(desk.context).first)
    #expect(entry.kind == .work)
    #expect(entry.start == nine)
    #expect(entry.end == nil)
    #expect(entry.block === block)
    #expect(entry.workspace === desk.acme)
    let status = try desk.engine.settle(at: at(30))
    #expect(status == TimerStatus(state: .working, plannedEnd: at(90), blockTimeLeft: 3600, breakTimeLeft: nil))
}

@Test func `start without a length takes the workspace's default length`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.globex, at: nine)
    #expect(try blocks(desk.context).first?.plannedMinutes == 45)
}

@Test func `start gives the block and its entries the chosen project`() throws {
    let desk = try Desk()
    let webShop = Project(name: "Web shop", workspace: desk.acme)
    desk.context.insert(webShop)

    try desk.engine.start(desk.acme, project: webShop, at: nine)
    try desk.engine.startBreak(at: at(10))

    #expect(try blocks(desk.context).first?.project === webShop)
    #expect(try entries(desk.context).allSatisfy { $0.project === webShop })
}

@Test func `start while a block runs ends that block and its entry at the same instant`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    try desk.engine.start(desk.personal, minutes: 30, at: at(20))

    let all = try blocks(desk.context)
    #expect(all.map(\.state) == [.done, .running])
    #expect(all[1].plannedStart == at(20))
    #expect(try entries(desk.context).map(\.end) == [at(20), nil])
    #expect(try desk.engine.settle(at: at(20)).plannedEnd == at(50))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `start while paused or on a break ends the old block too`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(10))
    try desk.engine.start(desk.globex, at: at(20))
    try desk.engine.startBreak(at: at(30))

    try desk.engine.start(desk.personal, at: at(32))

    #expect(try blocks(desk.context).map(\.state) == [.done, .done, .running])
    #expect(try entries(desk.context).map(\.kind) == [.work, .work, .break, .work])
    try expectHistoryKeepsRules(desk.context)
}

@Test func `start ends a running entry that has no block`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.globex, start: nine, end: nil, source: .manual))

    try desk.engine.start(desk.acme, at: at(5))

    #expect(try entries(desk.context).map(\.end) == [at(5), nil])
    try expectHistoryKeepsRules(desk.context)
}

@Test func `pause ends the running entry and keeps the block open`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    try desk.engine.pause(at: at(20))

    #expect(try entries(desk.context).map(\.end) == [at(20)])
    #expect(try blocks(desk.context).first?.state == .running)
    #expect(try desk.engine.settle(at: at(20)).state == .paused)
}

@Test func `while paused the time left stands still and the planned end moves later`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(20))

    let soon = try desk.engine.settle(at: at(25))
    let later = try desk.engine.settle(at: at(50))

    #expect(soon.blockTimeLeft == 40.0 * 60)
    #expect(later.blockTimeLeft == 40.0 * 60)
    #expect(soon.plannedEnd == at(65))
    #expect(later.plannedEnd == at(90))
}

@Test func `resume starts a new work entry and the block ends later by the pause`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(20))

    try desk.engine.resume(at: at(32))

    let all = try entries(desk.context)
    #expect(all.count == 2)
    #expect(all[1].kind == .work)
    #expect(all[1].start == at(32))
    #expect(all[1].end == nil)
    #expect(try desk.engine.settle(at: at(40)) ==
        TimerStatus(state: .working, plannedEnd: at(72), blockTimeLeft: 32 * 60, breakTimeLeft: nil))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `start break ends the work entry and starts a five minute break in the block`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    try desk.engine.startBreak(at: at(20))

    let all = try entries(desk.context)
    #expect(all.map(\.kind) == [.work, .break])
    #expect(all[0].end == at(20))
    #expect(all[1].start == at(20))
    #expect(all[1].plannedMinutes == TimerEngine.defaultBreakMinutes)
    #expect(all[1].block === all[0].block)
    #expect(try desk.engine.settle(at: at(22)) ==
        TimerStatus(state: .onBreak, plannedEnd: at(60), blockTimeLeft: 38 * 60, breakTimeLeft: 3 * 60))
}

@Test func `a break does not move the block's end`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 10, at: at(20))
    #expect(try desk.engine.settle(at: at(25)).plannedEnd == at(60))
    try desk.engine.endBreak(at: at(28))

    #expect(try desk.engine.settle(at: at(40)).plannedEnd == at(60))
}

@Test func `end break ends the break and starts work at the same instant`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(at: at(20))

    try desk.engine.endBreak(at: at(23))

    let all = try entries(desk.context)
    #expect(all.map(\.kind) == [.work, .break, .work])
    #expect(all[1].end == at(23))
    #expect(all[2].start == at(23))
    #expect(try desk.engine.settle(at: at(23)).state == .working)
}

@Test func `a break ends by itself when its time is up and work continues from its end`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(at: at(20))

    let status = try desk.engine.settle(at: at(31))

    let all = try entries(desk.context)
    #expect(all.map(\.kind) == [.work, .break, .work])
    #expect(all[1].end == at(25))
    #expect(all[2].start == at(25))
    #expect(status == TimerStatus(state: .working, plannedEnd: at(60), blockTimeLeft: 29 * 60, breakTimeLeft: nil))
}

@Test func `a break that reaches the block's end is clipped there and the block ends`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 10, at: at(55))

    #expect(try desk.engine.settle(at: at(58)).breakTimeLeft == 2 * 60)
    #expect(try desk.engine.settle(at: at(70)) == .idle)

    let all = try entries(desk.context)
    #expect(all.map(\.kind) == [.work, .break])
    #expect(all[1].end == at(60))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `extend adds fifteen minutes by default and any number of minutes when given`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    try desk.engine.extend(at: at(10))
    #expect(try desk.engine.settle(at: at(10)).plannedEnd == at(75))
    try desk.engine.extend(by: 5, at: at(10))
    #expect(try desk.engine.settle(at: at(10)).plannedEnd == at(80))
    #expect(try blocks(desk.context).first?.plannedMinutes == 80)
}

@Test func `extend works while paused and on a break`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(10))
    try desk.engine.extend(at: at(10))
    try desk.engine.resume(at: at(10))
    try desk.engine.startBreak(at: at(20))
    try desk.engine.extend(by: 10, at: at(21))

    #expect(try desk.engine.settle(at: at(21)).plannedEnd == at(85))
}

@Test func `switch ends the block and starts one for the other workspace at its default length`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: nine)

    try desk.engine.switchTo(desk.globex, at: at(30))

    let all = try blocks(desk.context)
    #expect(all.map(\.state) == [.done, .running])
    #expect(all[1].workspace === desk.globex)
    #expect(all[1].plannedMinutes == 45)
    #expect(try entries(desk.context).map(\.end) == [at(30), nil])
    #expect(try desk.engine.settle(at: at(30)).plannedEnd == at(75))
}

@Test func `switch works while paused and on a break`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(10))
    try desk.engine.switchTo(desk.globex, at: at(15))
    try desk.engine.startBreak(at: at(20))
    try desk.engine.switchTo(desk.personal, at: at(22))

    #expect(try blocks(desk.context).map(\.state) == [.done, .done, .running])
    try expectHistoryKeepsRules(desk.context)
}

@Test func `end closes the running entry and the block now`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    try desk.engine.end(at: at(20))

    #expect(try entries(desk.context).map(\.end) == [at(20)])
    #expect(try blocks(desk.context).first?.state == .done)
    #expect(try desk.engine.settle(at: at(20)) == .idle)
}

@Test func `end while paused closes the block and leaves the history as it was`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(20))

    try desk.engine.end(at: at(40))

    #expect(try entries(desk.context).map(\.end) == [at(20)])
    #expect(try blocks(desk.context).first?.state == .done)
}

@Test(arguments: [TimerState.working, .paused, .onBreak])
func `end starts nothing, not even after the break or the block would have run out`(state: TimerState) throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    switch state {
    case .paused: try desk.engine.pause(at: at(10))
    case .onBreak: try desk.engine.startBreak(at: at(10))
    default: break
    }

    try desk.engine.end(at: at(12))

    // Past the 5-minute break and the 60-minute block: no return to work, no new block.
    #expect(try desk.engine.settle(at: at(120)) == .idle)
    let expectedEnds: [Date?] = switch state {
    case .paused: [at(10)]
    case .onBreak: [at(10), at(12)]
    default: [at(12)]
    }
    #expect(try entries(desk.context).map(\.end) == expectedEnds)
    #expect(try entries(desk.context).last?.kind == (state == .onBreak ? .break : .work))
    #expect(try blocks(desk.context).map(\.state) == [.done])
    try expectHistoryKeepsRules(desk.context)
}

@Test func `time is up ends the entry and the block at the planned end`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    #expect(try desk.engine.settle(at: at(59)).blockTimeLeft == 60)
    #expect(try desk.engine.settle(at: at(60)) == .idle)

    #expect(try entries(desk.context).map(\.end) == [at(60)])
    #expect(try blocks(desk.context).first?.state == .done)
}

@Test func `time is up after a pause counts the pause`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(20))
    try desk.engine.resume(at: at(30))

    #expect(try desk.engine.settle(at: at(69)).state == .working)
    #expect(try desk.engine.settle(at: at(70)) == .idle)
    #expect(try entries(desk.context).last?.end == at(70))
}
