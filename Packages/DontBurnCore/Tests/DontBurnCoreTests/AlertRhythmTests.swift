@testable import DontBurnCore
import Foundation
import Testing

// Card #58: the end of a focus interval is announced, and a break that leaves
// the block waiting says so and holds the block's other alerts back.

/// Every alert switched on, notification and sound.
private let everything = AlertSettings(notifications: Set(AlertKind.allCases), sounds: Set(AlertKind.allCases))

/// The alert `due` reports between two settles of the engine, at `then` and at `now`.
private func due(_ desk: Desk, from then: Date, to now: Date) throws -> AlertKind? {
    let previous = try desk.engine.settle(at: then)
    let rhythm = try desk.engine.rhythm(at: then)
    let current = try desk.engine.settle(at: now)
    return AlertKind.due(from: previous, rhythm: rhythm, at: then, to: current, at: now)
}

/// The notifications planned for Acme's running block at `now`.
private func plan(_ desk: Desk, at now: Date, settings: AlertSettings = .standard) throws -> [PlannedAlert] {
    try PlannedAlert.plan(
        for: desk.engine.settle(at: now), rhythm: desk.engine.rhythm(at: now),
        workspace: "Acme", settings: settings, at: now,
    )
}

/// A desk whose Acme follows a waiting 25/5 and runs a block of `minutes` from nine.
private func runningOnWaiting(minutes: Int = 60) throws -> Desk {
    let desk = try Desk()
    try desk.acmeFollows(waitingPreset())
    try desk.engine.start(desk.acme, minutes: minutes, at: nine)
    return desk
}

// MARK: - The sound

struct AlertDueInARhythmTests {
    @Test func `the end of a focus interval is due, at the later settle and not at the earlier one`() throws {
        let desk = try runningOn25(minutes: 120)
        #expect(try due(desk, from: at(24.9), to: at(24.99)) == nil)
        #expect(try due(desk, from: at(24.9), to: at(25)) == .focusEnd)
        #expect(try due(desk, from: at(25), to: at(25.1)) == nil)
    }

    @Test func `a focus end sounds up to a minute late, and not later`() throws {
        let desk = try runningOn25(minutes: 120)
        #expect(try due(desk, from: at(24.9), to: at(25) + 59) == .focusEnd)
        #expect(try due(desk, from: at(24.9), to: at(25) + 60) == nil)
        #expect(try due(desk, from: at(20), to: at(50)) == nil)
    }

    @Test func `a skipped break ends without a sound, and the next focus end sounds again`() throws {
        let desk = try runningOn25(minutes: 120)
        #expect(try due(desk, from: at(29.9), to: at(30.1)) == nil)
        #expect(try due(desk, from: at(54.9), to: at(55.1)) == .focusEnd)
    }

    @Test func `a focus end is silent while paused, and sounds later by the pause`() throws {
        let desk = try runningOn25(minutes: 120)
        try desk.engine.pause(at: at(20))
        #expect(try due(desk, from: at(24.9), to: at(25.1)) == nil)

        try desk.engine.resume(at: at(40))
        #expect(try due(desk, from: at(44.9), to: at(45.1)) == .focusEnd)
    }

    @Test func `after a break taken by hand the focus end comes a full interval after it`() throws {
        let desk = try runningOn25(minutes: 120)
        try desk.engine.startBreak(minutes: 15, at: at(10))
        #expect(try due(desk, from: at(24.9), to: at(25.1)) == .breakEnd)
        #expect(try due(desk, from: at(49.9), to: at(50.1)) == .focusEnd)
    }

    @Test func `without a rhythm, or with no break that fits, no focus end is due`() throws {
        let plain = try Desk()
        try plain.engine.start(plain.acme, minutes: 120, at: nine)
        #expect(try due(plain, from: at(24.9), to: at(25.1)) == nil)

        // 28 minutes, so the warning is not on the same moment.
        #expect(try due(runningOn25(minutes: 28), from: at(24.9), to: at(25.1)) == nil)
    }

    @Test(arguments: [TimerState.paused, .onBreak, .idle])
    func `a focus end is silent when the block no longer works by then`(state: TimerState) throws {
        let desk = try runningOn25(minutes: 120)
        let previous = try desk.engine.settle(at: at(24.9))
        let rhythm = try desk.engine.rhythm(at: at(24.9))
        let current = TimerStatus(state: state, plannedEnd: at(120), blockTimeLeft: 5694, breakTimeLeft: nil)
        #expect(AlertKind.due(from: previous, rhythm: rhythm, at: at(24.9), to: current, at: at(25.1)) == nil)
    }

    @Test func `a focus end on the same moment as the warning wins over it`() throws {
        let desk = try runningOn25(minutes: 60)
        let previous = try desk.engine.settle(at: at(24.9))
        let rhythm = try desk.engine.rhythm(at: at(24.9))
        // The same block, 35 minutes shorter as a status, puts the warning on minute 25.
        let ending = TimerStatus(state: .working, plannedEnd: at(30), blockTimeLeft: 306, breakTimeLeft: nil)
        let current = TimerStatus(state: .working, plannedEnd: at(30), blockTimeLeft: 294, breakTimeLeft: nil)
        #expect(previous.state == .working)
        #expect(AlertKind.due(from: ending, rhythm: rhythm, at: at(24.9), to: current, at: at(25.1)) == .focusEnd)
        #expect(AlertKind.due(from: ending, at: at(24.9), to: current, at: at(25.1)) == .warning)
    }

    @Test func `the block's end wins over a focus end on the same moment`() throws {
        let desk = try runningOn25(minutes: 60)
        let rhythm = try desk.engine.rhythm(at: at(24.9))
        let ending = TimerStatus(state: .working, plannedEnd: at(25), blockTimeLeft: 6, breakTimeLeft: nil)
        #expect(AlertKind.due(from: ending, rhythm: rhythm, at: at(24.9), to: .idle, at: at(25.1)) == .blockEnd)
    }

    @Test func `a break end wins over a focus end on the same moment`() throws {
        let desk = try runningOn25(minutes: 120)
        let rhythm = try desk.engine.rhythm(at: at(24.9))
        let resting = TimerStatus(state: .onBreak, plannedEnd: at(120), blockTimeLeft: 5706, breakTimeLeft: 6)
        let current = TimerStatus(state: .working, plannedEnd: at(120), blockTimeLeft: 5694, breakTimeLeft: nil)
        #expect(AlertKind.due(from: resting, rhythm: rhythm, at: at(24.9), to: current, at: at(25.1)) == .breakEnd)
    }

    @Test func `a break that ends with the block waiting sounds as the break end, and a late one is silent`() throws {
        let desk = try runningOnWaiting()
        try desk.engine.startBreak(minutes: 5, at: at(25))
        #expect(try due(desk, from: at(29.9), to: at(30.1)) == .breakEnd)
        #expect(try desk.engine.settle(at: at(30.1)).state == .paused)
        #expect(try due(desk, from: at(30.1), to: at(60.1)) == nil)

        let asleep = try runningOnWaiting()
        try asleep.engine.startBreak(minutes: 5, at: at(25))
        #expect(try due(asleep, from: at(26), to: at(40)) == nil)
    }

    @Test func `while a block waits, its old warning and its old end stay silent`() throws {
        let desk = try runningOnWaiting()
        try desk.engine.startBreak(minutes: 4, at: at(50))
        // The break is over at 54, so the warning of minute 55 never comes.
        #expect(try due(desk, from: at(53.9), to: at(55.1)) == nil)
        #expect(try due(desk, from: at(59.9), to: at(60.1)) == nil)
        #expect(try desk.engine.settle(at: at(61)).state == .paused)
    }

    @Test func `a waiting break cut off at the block's end sounds as the block end`() throws {
        let desk = try runningOnWaiting()
        try desk.engine.startBreak(minutes: 5, at: at(57))
        #expect(try due(desk, from: at(59.9), to: at(60.1)) == .blockEnd)
    }
}

// MARK: - The notifications

struct AlertPlanInARhythmTests {
    @Test func `a working block plans its end and the end of its focus interval, which names the break`() throws {
        let desk = try runningOn25(minutes: 120)
        #expect(try plan(desk, at: at(10)) == [
            PlannedAlert(kind: .blockEnd, date: at(120), workspace: "Acme"),
            PlannedAlert(kind: .focusEnd, date: at(25), workspace: "Acme", breakMinutes: 5),
        ])
    }

    @Test func `one focus end is planned at most, and it stays the same until it passed`() throws {
        let desk = try runningOn25(minutes: 120)
        let first = try plan(desk, at: nine)
        for minute in [1.0, 10, 24.99] {
            #expect(try plan(desk, at: at(minute)) == first)
        }
        // Whether the next one waits until this break is taken or skipped is open here.
        #expect(try plan(desk, at: at(25)).filter { $0.kind == .focusEnd && $0.date == at(25) }.isEmpty)
        #expect(try plan(desk, at: at(27)).count { $0.kind == .focusEnd } <= 1)
        #expect(try plan(desk, at: at(31)).filter { $0.kind == .focusEnd }.map(\.date) == [at(55)])
    }

    @Test func `a long break's focus end names its own minutes`() throws {
        let desk = try runningOn25(minutes: 150)
        for minute in [25.0, 55, 85] {
            try desk.engine.startBreak(minutes: 5, at: at(minute))
        }
        #expect(try plan(desk, at: at(95)).first { $0.kind == .focusEnd } == PlannedAlert(
            kind: .focusEnd, date: at(115), workspace: "Acme", breakMinutes: 15,
        ))
    }

    @Test func `with no break left before the block's end only the block's end is planned`() throws {
        #expect(try plan(runningOn25(minutes: 30), at: at(10)).map(\.kind) == [.blockEnd])
        #expect(try plan(runningOn25(minutes: 60), at: at(31)).map(\.kind) == [.blockEnd])
    }

    @Test func `the focus end is planned only with its switch on, whatever its sound's`() throws {
        let desk = try runningOn25(minutes: 120)
        var settings = AlertSettings.standard
        settings.notifications.remove(.focusEnd)
        #expect(try plan(desk, at: at(10), settings: settings).map(\.kind) == [.blockEnd])

        settings = .standard
        settings.sounds.remove(.focusEnd)
        #expect(try plan(desk, at: at(10), settings: settings).map(\.kind) == [.blockEnd, .focusEnd])
    }

    @Test func `a pause plans nothing, and after it the focus end comes later by the pause`() throws {
        let desk = try runningOn25(minutes: 120)
        try desk.engine.pause(at: at(20))
        #expect(try plan(desk, at: at(30)).isEmpty)

        try desk.engine.resume(at: at(40))
        #expect(try plan(desk, at: at(41)).filter { $0.kind == .focusEnd }.map(\.date) == [at(45)])
    }

    @Test func `+15 moves the block's end and keeps the focus end`() throws {
        let desk = try runningOn25(minutes: 60)
        try desk.engine.extend(by: 15, at: at(10))
        #expect(try plan(desk, at: at(10)).map(\.date) == [at(75), at(25)])
    }

    @Test func `a break that resumes plans its end, the block's end and the focus end after it`() throws {
        let desk = try runningOn25(minutes: 120)
        try desk.engine.startBreak(minutes: 5, at: at(25))
        #expect(try plan(desk, at: at(26)) == [
            PlannedAlert(kind: .blockEnd, date: at(120), workspace: "Acme"),
            PlannedAlert(kind: .breakEnd, date: at(30), workspace: "Acme"),
            PlannedAlert(kind: .focusEnd, date: at(55), workspace: "Acme", breakMinutes: 5),
        ])
    }

    @Test func `a break after which the block waits plans its end alone, which says so`() throws {
        let desk = try runningOnWaiting(minutes: 120)
        try desk.engine.startBreak(minutes: 5, at: at(25))
        #expect(try plan(desk, at: at(26), settings: everything) == [
            PlannedAlert(kind: .breakEnd, date: at(30), workspace: "Acme", waitsForResume: true),
        ])
        #expect(try plan(desk, at: at(31), settings: everything).isEmpty)
    }

    @Test func `with the break end's switch off a break that waits plans nothing`() throws {
        let desk = try runningOnWaiting(minutes: 120)
        try desk.engine.startBreak(minutes: 5, at: at(25))
        var settings = everything
        settings.notifications.remove(.breakEnd)
        #expect(try plan(desk, at: at(26), settings: settings).isEmpty)
    }

    @Test func `after Resume the block's end and the next focus end are planned later`() throws {
        let desk = try runningOnWaiting(minutes: 120)
        try desk.engine.startBreak(minutes: 5, at: at(25))
        try desk.engine.resume(at: at(40))
        #expect(try plan(desk, at: at(41)).map(\.date) == [at(130), at(65)])
    }

    @Test func `a waiting break the block's end cuts off plans the block's end, not its own`() throws {
        let desk = try runningOnWaiting()
        try desk.engine.startBreak(minutes: 30, at: at(50))
        #expect(try plan(desk, at: at(51), settings: everything) == [
            PlannedAlert(kind: .blockEnd, date: at(60), workspace: "Acme"),
            PlannedAlert(kind: .warning, date: at(55), workspace: "Acme"),
        ])
    }

    @Test func `a block without a rhythm plans what it did before presets`() throws {
        let desk = try Desk()
        try FocusPreset.seedDefaults(into: desk.context)
        try desk.engine.start(desk.acme, at: nine)
        #expect(try plan(desk, at: at(10), settings: everything) == [
            PlannedAlert(kind: .blockEnd, date: at(60), workspace: "Acme"),
            PlannedAlert(kind: .warning, date: at(55), workspace: "Acme"),
        ])
        try desk.engine.startBreak(minutes: 5, at: at(10))
        #expect(try plan(desk, at: at(11)) == [
            PlannedAlert(kind: .blockEnd, date: at(60), workspace: "Acme"),
            PlannedAlert(kind: .breakEnd, date: at(15), workspace: "Acme"),
        ])
    }
}
