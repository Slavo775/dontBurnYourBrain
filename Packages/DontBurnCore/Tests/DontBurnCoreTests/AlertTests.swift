@testable import DontBurnCore
import Foundation
import Testing

/// Every alert switched on, notification and sound.
private let everything = AlertSettings(notifications: Set(AlertKind.allCases), sounds: Set(AlertKind.allCases))

/// The alert `due` reports between two settles of the engine, at `then` and at `now`.
private func due(_ desk: Desk, from then: Date, to now: Date) throws -> AlertKind? {
    let previous = try desk.engine.settle(at: then)
    let current = try desk.engine.settle(at: now)
    return AlertKind.due(from: previous, at: then, to: current, at: now)
}

/// A working status with its planned end at `end`, as the engine reports it at `now`.
private func working(until end: Date, at now: Date) -> TimerStatus {
    TimerStatus(state: .working, plannedEnd: end, blockTimeLeft: end.timeIntervalSince(now), breakTimeLeft: nil)
}

struct AlertDueTests {
    @Test func `a block that runs out between two ticks is due as the block end`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        #expect(try due(desk, from: at(59.5), to: at(60)) == .blockEnd)
    }

    @Test func `a tick up to a minute late still plays the block end`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        #expect(try due(desk, from: at(59), to: at(60).addingTimeInterval(59)) == .blockEnd)
    }

    @Test func `a tick more than a minute late plays nothing`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        #expect(try due(desk, from: at(59), to: at(60).addingTimeInterval(61)) == nil)
    }

    @Test func `a block that ran out while the Mac slept plays nothing on wake`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        #expect(try due(desk, from: at(40), to: at(70)) == nil)
    }

    @Test func `the moment counts at the later settle and not at the earlier one`() {
        let end = at(60)
        let ran = AlertKind.due(from: working(until: end, at: at(59)), at: at(59), to: .idle, at: end)
        let before = AlertKind.due(from: working(until: end, at: end), at: end, to: .idle, at: at(60.5))
        #expect(ran == .blockEnd)
        #expect(before == nil)
    }

    @Test func `a block ended early by the user plays no block end`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        let previous = try desk.engine.settle(at: at(30))
        try desk.engine.end(at: at(30.1))
        let current = try desk.engine.settle(at: at(30.2))
        #expect(previous.state == .working)
        #expect(current.state == .idle)
        #expect(AlertKind.due(from: previous, at: at(30), to: current, at: at(30.2)) == nil)
    }

    @Test func `a break that runs out is due as the break end`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.startBreak(minutes: 5, at: at(30))
        #expect(try due(desk, from: at(34.9), to: at(35.1)) == .breakEnd)
    }

    @Test func `a break that ran out long ago plays nothing`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.startBreak(minutes: 5, at: at(30))
        #expect(try due(desk, from: at(31), to: at(40)) == nil)
    }

    @Test func `a break clipped at the block's end plays the block end, not the break end`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.startBreak(minutes: 5, at: at(58))
        #expect(try due(desk, from: at(59.9), to: at(60.1)) == .blockEnd)
    }

    @Test func `five minutes before the end the warning is due`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        #expect(try due(desk, from: at(54.9), to: at(55)) == .warning)
    }

    @Test func `the warning is due on a break too`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.startBreak(minutes: 2, at: at(54))
        #expect(try due(desk, from: at(54.9), to: at(55.1)) == .warning)
    }

    @Test func `a block that started inside the last five minutes has no warning`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, minutes: 3, at: nine)
        #expect(try due(desk, from: nine, to: at(0.5)) == nil)
    }

    @Test func `a tick with no moment in between plays nothing`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        #expect(try due(desk, from: at(10), to: at(11)) == nil)
    }

    @Test func `a paused block plays nothing at its old end`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.pause(at: at(59))
        #expect(try due(desk, from: at(59.5), to: at(61)) == nil)
        #expect(try desk.engine.settle(at: at(61)).state == .paused)
    }

    @Test func `nothing is due after idle`() {
        #expect(AlertKind.due(from: .idle, at: at(0), to: .idle, at: at(1)) == nil)
    }

    @Test func `a break with nothing running that runs out is due as the break end`() throws {
        let resting = try #require(IdleBreak(start: nine, end: at(5)))
        #expect(AlertKind.due(from: resting.status(at: at(4.9)), at: at(4.9), to: .idle, at: at(5.1)) == .breakEnd)
        #expect(AlertKind.due(from: resting.status(at: at(4.9)), at: at(4.9), to: .idle, at: at(5)) == .breakEnd)
    }

    @Test func `a break with nothing running plays its end up to a minute late, and not later`() throws {
        let resting = try #require(IdleBreak(start: nine, end: at(5)))
        let then = at(4.5)
        let late = at(5).addingTimeInterval(59)
        let tooLate = at(5).addingTimeInterval(61)
        #expect(AlertKind.due(from: resting.status(at: then), at: then, to: .idle, at: late) == .breakEnd)
        #expect(AlertKind.due(from: resting.status(at: then), at: then, to: .idle, at: tooLate) == nil)
    }

    @Test func `a break with nothing running ended early, or not over yet, plays nothing`() throws {
        let resting = try #require(IdleBreak(start: nine, end: at(15)))
        let previous = resting.status(at: at(3))
        #expect(AlertKind.due(from: previous, at: at(3), to: .idle, at: at(3.5)) == nil)
        #expect(AlertKind.due(from: previous, at: at(3), to: resting.status(at: at(4)), at: at(4)) == nil)
    }

    @Test func `a block started as a break with nothing running ends plays no break end`() throws {
        let resting = try #require(IdleBreak(start: nine, end: at(5)))
        let block = working(until: at(65), at: at(5.1))
        #expect(AlertKind.due(from: resting.status(at: at(4.9)), at: at(4.9), to: block, at: at(5.1)) == nil)
    }

    @Test func `a break with nothing running already over at the earlier settle plays nothing again`() throws {
        let resting = try #require(IdleBreak(start: nine, end: at(5)))
        #expect(AlertKind.due(from: resting.status(at: at(5)), at: at(5), to: .idle, at: at(5.1)) == nil)
    }
}

struct AlertPlanTests {
    @Test func `by default a working block plans its end and no warning`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        let status = try desk.engine.settle(at: at(10))
        let plan = PlannedAlert.plan(for: status, workspace: "Acme", settings: .standard, at: at(10))
        #expect(plan == [PlannedAlert(kind: .blockEnd, date: at(60), workspace: "Acme")])
    }

    @Test func `the standard settings switch the warning off and both ends on`() {
        #expect(AlertSettings.standard.notifications == [.blockEnd, .breakEnd])
        #expect(AlertSettings.standard.sounds == [.blockEnd, .breakEnd])
    }

    @Test func `with the warning on it is planned five minutes before the end`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        let status = try desk.engine.settle(at: at(10))
        let plan = PlannedAlert.plan(for: status, workspace: "Acme", settings: everything, at: at(10))
        #expect(plan.map(\.kind) == [.blockEnd, .warning])
        #expect(plan.map(\.date) == [at(60), at(55)])
    }

    @Test func `a warning whose moment passed is not planned`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        let status = try desk.engine.settle(at: at(56))
        let plan = PlannedAlert.plan(for: status, workspace: "Acme", settings: everything, at: at(56))
        #expect(plan.map(\.kind) == [.blockEnd])
    }

    @Test func `a break plans its end and the block's end`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.startBreak(minutes: 5, at: at(30))
        let status = try desk.engine.settle(at: at(31))
        let plan = PlannedAlert.plan(for: status, workspace: "Acme", settings: .standard, at: at(31))
        #expect(plan.map(\.kind) == [.blockEnd, .breakEnd])
        #expect(plan.map(\.date) == [at(60), at(35)])
    }

    @Test func `a break clipped at the block's end plans the block's end alone`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.startBreak(minutes: 5, at: at(57))
        let status = try desk.engine.settle(at: at(58))
        let plan = PlannedAlert.plan(for: status, workspace: "Acme", settings: everything, at: at(58))
        #expect(plan == [PlannedAlert(kind: .blockEnd, date: at(60), workspace: "Acme")])
    }

    @Test func `a paused block plans nothing`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.pause(at: at(20))
        let status = try desk.engine.settle(at: at(21))
        #expect(PlannedAlert.plan(for: status, workspace: "Acme", settings: everything, at: at(21)).isEmpty)
    }

    @Test func `nothing running plans nothing`() {
        #expect(PlannedAlert.plan(for: .idle, workspace: "", settings: everything, at: nine).isEmpty)
    }

    @Test func `a block past its end plans nothing`() {
        let status = working(until: at(60), at: at(60))
        #expect(PlannedAlert.plan(for: status, workspace: "Acme", settings: everything, at: at(60)).isEmpty)
    }

    @Test func `after a resume the block's end is planned later by the pause`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.pause(at: at(20))
        try desk.engine.resume(at: at(30))
        let status = try desk.engine.settle(at: at(31))
        let plan = PlannedAlert.plan(for: status, workspace: "Acme", settings: .standard, at: at(31))
        #expect(plan.map(\.date) == [at(70)])
    }

    @Test func `after an extension the block's end is planned later`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.extend(by: 15, at: at(50))
        let status = try desk.engine.settle(at: at(51))
        let plan = PlannedAlert.plan(for: status, workspace: "Acme", settings: everything, at: at(51))
        #expect(plan.map(\.date) == [at(75), at(70)])
    }

    @Test func `only the notifications switched on are planned`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.acme, at: nine)
        try desk.engine.startBreak(minutes: 5, at: at(30))
        let status = try desk.engine.settle(at: at(31))
        let breakOnly = AlertSettings(notifications: [.breakEnd], sounds: Set(AlertKind.allCases))
        let none = AlertSettings(notifications: [], sounds: Set(AlertKind.allCases))
        let planned = PlannedAlert.plan(for: status, workspace: "Acme", settings: breakOnly, at: at(31))
        #expect(planned.map(\.kind) == [.breakEnd])
        #expect(PlannedAlert.plan(for: status, workspace: "Acme", settings: none, at: at(31)).isEmpty)
    }

    @Test func `a break with nothing running plans its end alone, naming no workspace`() throws {
        let resting = try #require(IdleBreak(start: nine, end: at(15)))
        let status = resting.status(at: at(3))
        let plan = PlannedAlert.plan(for: status, workspace: "Acme", settings: everything, at: at(3))
        #expect(plan == [PlannedAlert(kind: .breakEnd, date: at(15), workspace: nil)])
    }

    @Test func `a break with nothing running plans the moved end after +15`() throws {
        var resting = try #require(IdleBreak(start: nine, end: at(5)))
        resting.extend(by: 15)
        let plan = PlannedAlert.plan(for: resting.status(at: at(3)), workspace: "", settings: .standard, at: at(3))
        #expect(plan.map(\.date) == [at(20)])
    }

    @Test func `a break with nothing running plans nothing with its switch off or at its end`() throws {
        let resting = try #require(IdleBreak(start: nine, end: at(15)))
        let noBreakEnd = AlertSettings(notifications: [.blockEnd, .warning], sounds: Set(AlertKind.allCases))
        let status = resting.status(at: at(3))
        #expect(PlannedAlert.plan(for: status, workspace: "", settings: noBreakEnd, at: at(3)).isEmpty)
        let over = resting.status(at: at(15))
        #expect(PlannedAlert.plan(for: over, workspace: "", settings: everything, at: at(15)).isEmpty)
    }

    @Test func `the plan names the running block's workspace`() throws {
        let desk = try Desk()
        try desk.engine.start(desk.globex, at: nine)
        let status = try desk.engine.settle(at: at(1))
        let plan = PlannedAlert.plan(for: status, workspace: "Globex", settings: everything, at: at(1))
        #expect(!plan.isEmpty)
        #expect(plan.allSatisfy { $0.workspace == "Globex" })
    }
}
