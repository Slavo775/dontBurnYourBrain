@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// After a restart the engine works from the stored times alone: a new context
// and a new engine on the same store give the same answers.

@Test func `after a restart in the middle of a block the time left is right`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    let (engine, context) = desk.restarted()
    let status = try engine.settle(at: at(35))

    #expect(status == TimerStatus(state: .working, plannedEnd: at(60), blockTimeLeft: 25 * 60, breakTimeLeft: nil))
    try engine.pause(at: at(40))
    #expect(try entries(context).map(\.end) == [at(40)])
}

@Test func `after a restart during a pause the time left has not moved`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(20))

    let (engine, context) = desk.restarted()
    let status = try engine.settle(at: at(200))

    #expect(status.state == .paused)
    #expect(status.blockTimeLeft == 40.0 * 60)
    try engine.resume(at: at(200))
    #expect(try engine.settle(at: at(200)).plannedEnd == at(240))
    #expect(try entries(context).count == 2)
}

@Test func `after a restart during a break a ten minute break keeps its length`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 10, at: at(20))

    let (engine, context) = desk.restarted()
    let during = try engine.settle(at: at(26))

    #expect(during == TimerStatus(state: .onBreak, plannedEnd: at(60), blockTimeLeft: 34 * 60, breakTimeLeft: 4 * 60))
    #expect(try engine.settle(at: at(31)).state == .working)
    let all = try entries(context)
    #expect(all.map(\.kind) == [.work, .break, .work])
    #expect(all[1].plannedMinutes == 10)
    #expect(all[1].end == at(30))
    #expect(all[2].start == at(30))
}

@Test func `after a restart later than the planned end the entry and block close at the planned end`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(10))
    try desk.engine.resume(at: at(15))

    let (engine, context) = desk.restarted()
    #expect(try engine.settle(at: at(600)) == .idle)

    #expect(try entries(context).map(\.end) == [at(10), at(65)])
    #expect(try blocks(context).first?.state == .done)
    try expectHistoryKeepsRules(context)
}

@Test func `after a restart long after a break, the break, the work after it and the block all close in time`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 10, at: at(20))

    let (engine, context) = desk.restarted()
    #expect(try engine.settle(at: at(600)) == .idle)

    let all = try entries(context)
    #expect(all.map(\.kind) == [.work, .break, .work])
    #expect(all.map(\.end) == [at(20), at(30), at(60)])
    try expectHistoryKeepsRules(context)
}

@Test func `a restart and a settle at the same moment change nothing more`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(at: at(20))
    let before = try desk.engine.settle(at: at(22))

    let (engine, context) = desk.restarted()

    #expect(try engine.settle(at: at(22)) == before)
    #expect(try engine.settle(at: at(22)) == before)
    #expect(try entries(context).count == 2)
}
