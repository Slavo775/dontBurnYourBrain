@testable import DontBurnCore
import Foundation
import Testing

// Card #58: the panel's line, its gaps and the break that Break starts at once,
// for a block with a rhythm. A block without one keeps its phase 1 panel.

/// What the panel shows for Acme's running block at `now`.
private func panel(_ desk: Desk, at now: Date) throws -> CompactPanel {
    try #require(try CompactPanel(
        status: desk.engine.settle(at: now),
        block: desk.engine.runningBlock(),
        rhythm: desk.engine.rhythm(at: now),
        tracked: 0,
    ))
}

/// The panel's line for Acme's running block at `now`.
private func line(_ desk: Desk, at now: Date) throws -> CompactPanel.Line {
    try panel(desk, at: now).line
}

/// A desk whose Acme follows a waiting 25/5 and runs a block of `minutes` from nine.
private func runningOnWaiting(minutes: Int = 60) throws -> Desk {
    let desk = try Desk()
    try desk.acmeFollows(waitingPreset())
    try desk.engine.start(desk.acme, minutes: minutes, at: nine)
    return desk
}

// MARK: - While working

@Test(arguments: [
    (0.0, 25), (0.01, 24), (6, 19), (6.5, 18), (23.99, 1), (24, 1), (24.01, 0), (24.99, 0),
] as [(Double, Int)])
func `the line says how many whole minutes are left until the next break, rounded down`(
    minute: Double, left: Int,
) throws {
    let desk = try runningOn25(minutes: 120)

    #expect(try line(desk, at: at(minute)) == .breakIn("2:00", minutes: left))
}

@Test(arguments: [25.0, 27, 29.99])
func `while a break is due the line names its planned length, and Break starts that one`(minute: Double) throws {
    let desk = try runningOn25(minutes: 120)

    let shown = try panel(desk, at: at(minute))

    #expect(shown.line == .breakDue("2:00", minutes: 5))
    #expect(shown.dueBreakMinutes == 5)
}

@Test func `a due long break names its own length`() throws {
    let desk = try runningOn25(minutes: 150)
    for minute in [25.0, 55, 85] {
        try desk.engine.startBreak(minutes: 5, at: at(minute))
    }

    let shown = try panel(desk, at: at(116))

    #expect(shown.line == .breakDue("2:30", minutes: 15))
    #expect(shown.dueBreakMinutes == 15)
}

@Test func `before a break is due and after it is skipped, Break starts none at once`() throws {
    let desk = try runningOn25(minutes: 120)

    #expect(try panel(desk, at: at(24.99)).dueBreakMinutes == nil)
    #expect(try panel(desk, at: at(30)).dueBreakMinutes == nil)
    #expect(try line(desk, at: at(30)) == .breakIn("2:00", minutes: 25))
}

@Test func `with no break left before the block's end the line names the block alone`() throws {
    #expect(try line(runningOn25(minutes: 30), at: at(10)) == .leftOf("0:30"))
    #expect(try line(runningOn25(minutes: 60), at: at(31)) == .leftOf("1:00"))
}

@Test func `+15 that brings a break back names it`() throws {
    let desk = try runningOn25(minutes: 60)
    #expect(try line(desk, at: at(40)) == .leftOf("1:00"))

    try desk.engine.extend(by: 15, at: at(40))

    #expect(try line(desk, at: at(40)) == .breakIn("1:15", minutes: 15))
}

@Test func `after a pause the line counts on where it stood`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.pause(at: at(10))
    #expect(try line(desk, at: at(40)) == .paused)

    try desk.engine.resume(at: at(40))

    #expect(try line(desk, at: at(40)) == .breakIn("2:00", minutes: 15))
}

@Test func `after a break taken by hand the line counts a full focus interval`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.startBreak(minutes: 15, at: at(10))

    #expect(try line(desk, at: at(25)) == .breakIn("2:00", minutes: 25))
}

@Test func `with the clock moved back the line counts from that time to the same break`() throws {
    let desk = try runningOn25(minutes: 120)

    #expect(try line(desk, at: at(-5)) == .breakIn("2:00", minutes: 30))
}

// MARK: - Paused

@Test func `while paused Break starts no due break, and the gaps stay`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.pause(at: at(27))

    let shown = try panel(desk, at: at(40))

    #expect(shown.line == .paused)
    #expect(shown.dueBreakMinutes == nil)
    #expect(shown.gaps.count == 3)
}

// MARK: - On a break

@Test func `on a planned break the line says how long it lasts and what follows`() throws {
    let resuming = try runningOn25()
    try resuming.engine.startBreak(minutes: 5, at: at(25))
    #expect(try line(resuming, at: at(26)) == .rhythmBreak(minutes: 5, returnTo: "Acme"))
    #expect(try line(resuming, at: at(29.99)) == .rhythmBreak(minutes: 5, returnTo: "Acme"))

    let waiting = try runningOnWaiting()
    try waiting.engine.startBreak(minutes: 5, at: at(25))
    #expect(try line(waiting, at: at(26)) == .rhythmBreakThenPaused(minutes: 5))
}

@Test func `a break taken by hand says the length it was given, and +15 the longer one`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.startBreak(minutes: 30, at: at(10))
    #expect(try line(desk, at: at(11)) == .rhythmBreak(minutes: 30, returnTo: "Acme"))

    try desk.engine.extend(by: 15, at: at(11))

    #expect(try line(desk, at: at(11)) == .rhythmBreak(minutes: 45, returnTo: "Acme"))
}

@Test func `a break the block's end cuts off says how long it really lasts, also with a preset that waits`() throws {
    let resuming = try runningOn25()
    try resuming.engine.startBreak(minutes: 30, at: at(57))
    #expect(try line(resuming, at: at(58)) == .rhythmBreak(minutes: 3, returnTo: "Acme"))

    let waiting = try runningOnWaiting()
    try waiting.engine.startBreak(minutes: 30, at: at(57))
    #expect(try line(waiting, at: at(58)) == .rhythmBreak(minutes: 3, returnTo: "Acme"))
}

@Test func `a break cut off below a minute has no length to name`() throws {
    let desk = try runningOn25()
    try desk.engine.startBreak(minutes: 5, at: at(59.5))

    #expect(try line(desk, at: at(59.6)) == .onBreak(returnTo: "Acme"))
}

@Test func `a break of exactly one minute names it`() throws {
    let desk = try runningOn25()
    try desk.engine.startBreak(minutes: 5, at: at(59))

    #expect(try line(desk, at: at(59.5)) == .rhythmBreak(minutes: 1, returnTo: "Acme"))
}

@Test func `on a break with nothing running there are no gaps and no due break`() throws {
    let resting = try #require(IdleBreak(start: nine, end: at(15)))

    let shown = CompactPanel(idleBreak: resting, at: at(2), tracked: 0)

    #expect(shown.gaps.isEmpty)
    #expect(shown.dueBreakMinutes == nil)
}

// MARK: - Without a rhythm

@Test func `a block without a rhythm shows what it did before presets, in every state`() throws {
    let desk = try Desk()
    try FocusPreset.seedDefaults(into: desk.context)
    try desk.engine.start(desk.acme, minutes: 120, at: nine)

    func expectPlain(_ line: CompactPanel.Line, at now: Date) throws {
        let shown = try panel(desk, at: now)
        #expect(shown.line == line)
        #expect(shown.gaps.isEmpty)
        #expect(shown.dueBreakMinutes == nil)
        #expect(try shown == CompactPanel(
            status: desk.engine.settle(at: now), block: desk.engine.runningBlock(), tracked: 0,
        ))
    }

    try expectPlain(.leftOf("2:00"), at: at(26))
    try desk.engine.startBreak(minutes: 5, at: at(30))
    try expectPlain(.onBreak(returnTo: "Acme"), at: at(31))
    try desk.engine.pause(at: at(40))
    try expectPlain(.paused, at: at(45))
}

// MARK: - The gaps

@Test func `the panel carries the rhythm's gaps as fractions of the block's planned length`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.startBreak(minutes: 5, at: at(25))

    let shown = try panel(desk, at: at(36))

    #expect(shown.gaps.map { Int(($0.lowerBound * 120).rounded()) } == [25, 55, 85])
    #expect(shown.gaps.map { Int(($0.upperBound * 120).rounded()) } == [30, 60, 90])
}
