@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// Card #57: "wait for me" after a break, a workspace with no preset, and the
// ceiling on a very long plan.

// MARK: - Wait for me

@Test func `with wait for me 50/10 waits paused after its break, and its end moves later until Resume`() throws {
    let desk = try Desk()
    try desk.acmeFollows(waitingPreset(focus: 50, break: 10))
    try desk.engine.start(desk.acme, minutes: 120, at: nine)
    let due = try checkedRhythm(desk.engine, at: at(50))
    #expect(due.isBreakDue)
    try desk.engine.startBreak(minutes: #require(due.nextBreakMinutes), at: at(50))

    #expect(try desk.engine.settle(at: at(70)) == TimerStatus(
        state: .paused, plannedEnd: at(130), blockTimeLeft: 60 * 60, breakTimeLeft: nil,
    ))
    let history = try entries(desk.context)
    #expect(history.map(\.kind) == [.work, .break])
    #expect(history.map(\.end) == [at(50), at(60)])
    let paused = try checkedRhythm(desk.engine, at: at(70))
    #expect(paused.current.kind == .focus)
    #expect(paused.roundsDone == 1)

    try desk.engine.resume(at: at(75))
    #expect(try desk.engine.settle(at: at(75)) == TimerStatus(
        state: .working, plannedEnd: at(135), blockTimeLeft: 60 * 60, breakTimeLeft: nil,
    ))
    try expectHistoryKeepsRules(desk.context)
}

@Test func `with wait for me a break taken by hand also leaves the block paused at its planned end`() throws {
    let desk = try Desk()
    try desk.acmeFollows(waitingPreset())
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 15, at: at(10))

    #expect(try desk.engine.settle(at: at(30)) == TimerStatus(
        state: .paused, plannedEnd: at(65), blockTimeLeft: 35 * 60, breakTimeLeft: nil,
    ))
    #expect(try entries(desk.context).map(\.end) == [at(10), at(25)])
}

@Test func `with wait for me ending a break by hand still starts work at once`() throws {
    let desk = try Desk()
    try desk.acmeFollows(waitingPreset())
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.startBreak(minutes: 5, at: at(25))
    try desk.engine.endBreak(at: at(28))

    #expect(try desk.engine.settle(at: at(40)).state == .working)
    let history = try entries(desk.context)
    #expect(history.map(\.kind) == [.work, .break, .work])
    #expect(history.map(\.start) == [at(0), at(25), at(28)])
    #expect(history.last?.end == nil)
}

@Test func `a block without a rhythm always resumes after a break, even when its preset says wait`() throws {
    let desk = try Desk()
    let noBreaks = FocusPreset(name: "No breaks", focusMinutes: 25, breakMinutes: 0, resumesAfterBreak: false)
    try desk.acmeFollows(noBreaks)
    try desk.engine.start(desk.acme, at: nine)
    #expect(try desk.engine.rhythm(at: nine) == nil)

    try desk.engine.startBreak(minutes: 5, at: at(10))

    #expect(try desk.engine.settle(at: at(16)).state == .working)
    #expect(try entries(desk.context).map(\.start) == [at(0), at(10), at(15)])
}

// MARK: - No preset

/// Runs one block in Acme through each operation and returns the status after each.
private func phaseOneStatuses(on desk: Desk) throws -> [TimerStatus] {
    let engine = desk.engine
    var statuses: [TimerStatus] = []
    func look(at minute: Double) throws {
        #expect(try engine.rhythm(at: at(minute)) == nil)
        try statuses.append(engine.settle(at: at(minute)))
    }
    try engine.start(desk.acme, at: nine)
    try look(at: 10)
    try engine.startBreak(minutes: 5, at: at(25))
    try look(at: 27)
    try look(at: 31)
    try engine.pause(at: at(40))
    try look(at: 50)
    try engine.resume(at: at(50))
    try engine.extend(by: 15, at: at(50))
    try look(at: 50)
    try look(at: 200)
    return statuses
}

@Test func `a workspace without a preset has no rhythm, and its timer reports what it did before presets`() throws {
    let withoutPresets = try Desk()
    let withPresets = try Desk()
    try FocusPreset.seedDefaults(into: withPresets.context)

    let expected = [
        TimerStatus(state: .working, plannedEnd: at(60), blockTimeLeft: 50 * 60, breakTimeLeft: nil),
        TimerStatus(state: .onBreak, plannedEnd: at(60), blockTimeLeft: 33 * 60, breakTimeLeft: 3 * 60),
        TimerStatus(state: .working, plannedEnd: at(60), blockTimeLeft: 29 * 60, breakTimeLeft: nil),
        TimerStatus(state: .paused, plannedEnd: at(70), blockTimeLeft: 20 * 60, breakTimeLeft: nil),
        TimerStatus(state: .working, plannedEnd: at(85), blockTimeLeft: 35 * 60, breakTimeLeft: nil),
        .idle,
    ]
    #expect(try phaseOneStatuses(on: withoutPresets) == expected)
    #expect(try phaseOneStatuses(on: withPresets) == expected)
    #expect(try entries(withPresets.context).map(\.end) == [at(25), at(30), at(40), at(85)])
    let block = try #require(try blocks(withPresets.context).first)
    #expect(rhythmCopy(of: block) == [0, 0, 0, 0])
    #expect(block.focusPreset == nil)
}

@Test func `rhythm is nil while nothing runs`() throws {
    let desk = try Desk()
    try desk.acmeFollowsSeeded("25/5")

    #expect(try desk.engine.rhythm(at: nine) == nil)
    try desk.engine.start(desk.acme, at: nine)
    try desk.engine.end(at: at(10))
    #expect(try desk.engine.rhythm(at: at(10)) == nil)
}

@Test func `a block started before its workspace got a preset has no rhythm, and the next block has one`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    try desk.acmeFollowsSeeded("25/5")

    #expect(try desk.engine.rhythm(at: at(30)) == nil)

    try desk.engine.start(desk.acme, at: at(30))
    #expect(try checkedRhythm(desk.engine, at: at(30)).current == focus(30, 55))
}

@Test func `switching to a workspace with a preset gives the new block that preset's rhythm`() throws {
    let desk = try Desk()
    try desk.acmeFollowsSeeded("50/10")
    try desk.engine.start(desk.globex, at: nine)
    #expect(try desk.engine.rhythm(at: at(10)) == nil)

    try desk.engine.switchTo(desk.acme, at: at(10))

    #expect(try checkedRhythm(desk.engine, at: at(10)) == FocusRhythm(
        current: focus(10, 70), isBreakDue: false, nextBreak: nil, nextBreakMinutes: nil,
        roundsDone: 0, plan: [focus(10, 70)],
    ))
}

// MARK: - The ceiling

@Test(.timeLimit(.minutes(1)), arguments: [100_000, Int.max])
func `a very long block caps its plan and the last interval still runs to the block's end`(minutes: Int) throws {
    let desk = try runningOn25(minutes: minutes)

    let rhythm = try checkedRhythm(desk.engine, at: at(10))

    #expect(rhythm.plan.count <= 1001)
    #expect(rhythm.current == focus(0, 25))
}
