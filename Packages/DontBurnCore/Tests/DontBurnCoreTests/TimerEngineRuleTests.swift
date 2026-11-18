@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// The rules the engine keeps, the empty store, refusals and a clock that moves back.

@Test func `an empty store reports nothing running and writes nothing`() throws {
    let desk = try Desk()

    #expect(try desk.engine.settle(at: nine) == .idle)
    #expect(TimerStatus.idle.plannedEnd == nil)
    #expect(TimerStatus.idle.blockTimeLeft == nil)
    #expect(try blocks(desk.context).isEmpty)
    #expect(try entries(desk.context).isEmpty)
}

@Test func `with nothing running every operation but start is refused and writes nothing`() throws {
    let desk = try Desk()
    let refused = TimerEngineError.notAllowed(.idle)

    #expect(throws: refused) { try desk.engine.pause(at: nine) }
    #expect(throws: refused) { try desk.engine.resume(at: nine) }
    #expect(throws: refused) { try desk.engine.startBreak(at: nine) }
    #expect(throws: refused) { try desk.engine.endBreak(at: nine) }
    #expect(throws: refused) { try desk.engine.extend(at: nine) }
    #expect(throws: refused) { try desk.engine.end(at: nine) }
    #expect(throws: refused) { try desk.engine.switchTo(desk.globex, at: nine) }
    #expect(try blocks(desk.context).isEmpty)
    #expect(try entries(desk.context).isEmpty)
}

@Test func `an operation that does not fit the state is refused with that state and changes nothing`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    #expect(throws: TimerEngineError.notAllowed(.working)) { try desk.engine.resume(at: at(5)) }
    #expect(throws: TimerEngineError.notAllowed(.working)) { try desk.engine.endBreak(at: at(5)) }
    try desk.engine.pause(at: at(10))
    #expect(throws: TimerEngineError.notAllowed(.paused)) { try desk.engine.pause(at: at(15)) }
    #expect(throws: TimerEngineError.notAllowed(.paused)) { try desk.engine.startBreak(at: at(15)) }
    #expect(throws: TimerEngineError.notAllowed(.paused)) { try desk.engine.endBreak(at: at(15)) }
    try desk.engine.resume(at: at(20))
    try desk.engine.startBreak(at: at(30))
    #expect(throws: TimerEngineError.notAllowed(.onBreak)) { try desk.engine.startBreak(at: at(31)) }
    #expect(throws: TimerEngineError.notAllowed(.onBreak)) { try desk.engine.resume(at: at(31)) }

    #expect(try entries(desk.context).map(\.kind) == [.work, .work, .break])
    #expect(try entries(desk.context).last?.end == nil)
}

@Test func `a length, break or extension of zero minutes or less is refused before anything changes`() throws {
    let desk = try Desk()
    #expect(throws: TimerEngineError.invalidMinutes) { try desk.engine.start(desk.acme, minutes: 0, at: nine) }
    #expect(throws: TimerEngineError.invalidMinutes) { try desk.engine.start(desk.acme, minutes: -5, at: nine) }
    desk.personal.defaultBlockMinutes = 0
    #expect(throws: TimerEngineError.invalidMinutes) { try desk.engine.start(desk.personal, at: nine) }

    try desk.engine.start(desk.acme, at: nine)
    #expect(throws: TimerEngineError.invalidMinutes) { try desk.engine.startBreak(minutes: 0, at: at(10)) }
    #expect(throws: TimerEngineError.invalidMinutes) { try desk.engine.extend(by: -15, at: at(10)) }
    #expect(throws: TimerEngineError.invalidMinutes) { try desk.engine.switchTo(desk.personal, at: at(10)) }

    #expect(try blocks(desk.context).count == 1)
    #expect(try blocks(desk.context).first?.plannedMinutes == 60)
    #expect(try desk.engine.settle(at: at(10)).state == .working)
}

@Test func `a project that cannot be assigned is refused and the running block keeps running`() throws {
    let desk = try Desk()
    let dataPlatform = Project(name: "Data platform", workspace: desk.globex)
    let reading = Project(name: "Reading", workspace: desk.acme, isTimeTracked: false)
    desk.context.insert(dataPlatform)
    desk.context.insert(reading)
    try desk.engine.start(desk.personal, at: nine)

    #expect(throws: ProjectAssignmentError.otherWorkspace) {
        try desk.engine.start(desk.acme, project: dataPlatform, at: at(5))
    }
    #expect(throws: ProjectAssignmentError.notTimeTracked) {
        try desk.engine.switchTo(desk.acme, project: reading, at: at(5))
    }

    #expect(try blocks(desk.context).count == 1)
    #expect(try desk.engine.settle(at: at(5)).state == .working)
}

@Test func `pausing a break ends it and resume starts work, not another break`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(at: at(20))

    try desk.engine.pause(at: at(22))
    #expect(try desk.engine.settle(at: at(40)).state == .paused)
    try desk.engine.resume(at: at(40))

    let all = try entries(desk.context)
    #expect(all.map(\.kind) == [.work, .break, .work])
    #expect(all[1].end == at(22))
    #expect(try desk.engine.settle(at: at(40)).plannedEnd == at(78))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `a paused block long past its planned end stays open with the same time left`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(50))

    let status = try desk.engine.settle(at: at(600))

    #expect(status.state == .paused)
    #expect(status.blockTimeLeft == 10.0 * 60)
    #expect(try blocks(desk.context).first?.state == .running)
}

@Test func `a running meeting entry counts as working`() throws {
    let desk = try Desk()
    let block = TimeBlock(workspace: desk.acme, plannedStart: nine, plannedMinutes: 60, state: .running)
    desk.context.insert(block)
    desk.context.insert(TimeEntry(workspace: desk.acme, start: nine, end: nil, kind: .meeting, block: block))

    #expect(try desk.engine.settle(at: at(10)).state == .working)
    try desk.engine.startBreak(at: at(10))
    #expect(try entries(desk.context).map(\.kind) == [.meeting, .break])
}

@Test func `a break without a planned length runs until it is ended or the block ends`() throws {
    let desk = try Desk()
    let block = TimeBlock(workspace: desk.acme, plannedStart: nine, plannedMinutes: 60, state: .running)
    desk.context.insert(block)
    desk.context.insert(TimeEntry(workspace: desk.acme, start: nine, end: nil, kind: .break, block: block))

    let status = try desk.engine.settle(at: at(30))
    #expect(status.state == .onBreak)
    #expect(status.breakTimeLeft == nil)
    #expect(try desk.engine.settle(at: at(61)) == .idle)
    #expect(try entries(desk.context).first?.end == at(60))
}

@Test func `a running block without entries reads as paused`() throws {
    let desk = try Desk()
    desk.context.insert(TimeBlock(workspace: desk.acme, plannedStart: nine, plannedMinutes: 60, state: .running))

    let status = try desk.engine.settle(at: at(30))

    #expect(status.state == .paused)
    #expect(status.blockTimeLeft == 60.0 * 60)
}

@Test func `a full day keeps one running entry, real intervals and no overlap`() throws {
    let desk = try Desk()
    let engine = desk.engine
    try engine.start(desk.acme, at: nine)
    try expectHistoryKeepsRules(desk.context)
    try engine.startBreak(at: at(25))
    try engine.settle(at: at(31))
    try engine.pause(at: at(40))
    try engine.resume(at: at(45))
    try engine.extend(at: at(50))
    try engine.switchTo(desk.globex, at: at(70))
    try engine.startBreak(minutes: 10, at: at(100))
    try engine.pause(at: at(105))
    try engine.resume(at: at(106))
    try engine.settle(at: at(200))
    try engine.start(desk.personal, minutes: 25, at: at(240))
    try engine.end(at: at(250))

    try expectHistoryKeepsRules(desk.context)
    #expect(try entries(desk.context).allSatisfy { $0.end != nil })
    #expect(try blocks(desk.context).allSatisfy { $0.state == .done })
}

@Test func `time between blocks belongs to nothing`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.settle(at: at(90))
    try desk.engine.start(desk.globex, at: at(120))

    let all = try entries(desk.context)
    #expect(all.map(\.end) == [at(60), nil])
    #expect(all[1].start == at(120))
}

@Test func `two running blocks in a damaged store: the newest counts and start ends both`() throws {
    let desk = try Desk()
    for (workspace, minute) in [(desk.acme, 0.0), (desk.globex, 10.0)] {
        let block = TimeBlock(workspace: workspace, plannedStart: at(minute), plannedMinutes: 60, state: .running)
        desk.context.insert(block)
        desk.context.insert(TimeEntry(workspace: workspace, start: at(minute), end: nil, block: block))
    }

    #expect(try desk.engine.settle(at: at(5)).plannedEnd == at(70))
    try desk.engine.start(desk.personal, at: at(20))

    #expect(try blocks(desk.context).map(\.state) == [.done, .done, .running])
    #expect(try entries(desk.context).count { $0.end == nil } == 1)
}

// MARK: - A clock that moves back

@Test func `a pause earlier than the entry's start ends the entry at its start`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: at(30))

    try desk.engine.pause(at: at(20))
    try desk.engine.resume(at: at(10))

    let all = try entries(desk.context)
    #expect(all[0].end == at(30))
    #expect(all[1].start == at(30))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `a start earlier than the running block's entries begins after them`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: at(30))
    try desk.engine.startBreak(at: at(40))
    try desk.engine.endBreak(at: at(42))

    try desk.engine.start(desk.globex, at: at(35))

    #expect(try blocks(desk.context).last?.plannedStart == at(42))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `a start earlier than a just ended block's entries does not overlap them`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.end(at: at(30))

    try desk.engine.start(desk.globex, at: at(29))

    #expect(try blocks(desk.context).last?.plannedStart == at(30))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `a start earlier than the end of a block whose time was up does not overlap it`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    #expect(try desk.engine.settle(at: at(90)) == .idle)

    #expect(throws: TimerEngineError.notAllowed(.idle)) { try desk.engine.switchTo(desk.globex, at: at(50)) }
    try desk.engine.start(desk.globex, at: at(50))

    #expect(try blocks(desk.context).last?.plannedStart == at(60))
    #expect(try entries(desk.context).last?.start == at(60))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `a resume earlier than the latest timer entry begins after it`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.pause(at: at(20))
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(20), end: at(40)))

    try desk.engine.resume(at: at(35))

    #expect(try entries(desk.context).last?.start == at(40))
    #expect(try entries(desk.context).last?.end == nil)
}

@Test func `an extension that would overflow the length is refused and changes nothing`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)

    #expect(throws: TimerEngineError.invalidMinutes) { try desk.engine.extend(by: Int.max, at: at(10)) }

    #expect(try blocks(desk.context).first?.plannedMinutes == 60)
    #expect(try desk.engine.settle(at: at(10)).plannedEnd == at(60))
}

@Test func `a future manual or calendar entry does not push the timer's start or resume later`() throws {
    let desk = try Desk()
    let meeting = TimeEntry(workspace: desk.acme, start: at(120), end: at(150), kind: .meeting, source: .calendar)
    desk.context.insert(meeting)
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(200), end: at(230), source: .manual))

    try desk.engine.start(desk.acme, at: nine)
    #expect(try blocks(desk.context).first?.plannedStart == nine)
    try desk.engine.pause(at: at(10))
    try desk.engine.resume(at: at(15))

    let timer = try entries(desk.context).filter { $0.source == .timer }
    #expect(timer.map(\.start) == [nine, at(15)])
}
