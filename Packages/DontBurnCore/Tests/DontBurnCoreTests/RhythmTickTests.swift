@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// Card #58: the moments a planned break becomes due or is skipped are ticks of
// their own, and the sample scenarios stand where they say.

/// A working status with `left` of the block to go.
private func working(left: TimeInterval) -> TimerStatus {
    TimerStatus(state: .working, plannedEnd: nine + left, blockTimeLeft: left, breakTimeLeft: nil)
}

/// The sample data in memory with `scenario` applied at nine.
private func sample(_ scenario: TimerScenario) throws -> (engine: TimerEngine, context: ModelContext) {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: nine)
    try scenario.apply(to: context, now: nine)
    return (TimerEngine(context: context), context)
}

/// What the panel shows for the running block at `now`.
private func panel(_ engine: TimerEngine, at now: Date) throws -> CompactPanel {
    try #require(try CompactPanel(
        status: engine.settle(at: now), block: engine.runningBlock(), rhythm: engine.rhythm(at: now), tracked: 0,
    ))
}

// MARK: - The tick

@Test(arguments: [35.3, 35.59, 40.3, 40.59])
func `while working the item is drawn again just after a break becomes due or is skipped`(minute: Double) throws {
    let desk = try runningOn25(minutes: 120)
    // The next break is due at 35.6 and skipped at 40.6, where no digit of the item changes.
    try desk.engine.startBreak(minutes: 5, at: at(10))
    try desk.engine.endBreak(at: at(10.6))
    let status = try desk.engine.settle(at: at(minute))
    let rhythm = try checkedRhythm(desk.engine, at: at(minute))

    let next = MenuBarLabel.nextRedraw(status: status, rhythm: rhythm, untrackedSince: nine, after: at(minute))

    #expect(next > rhythm.current.end)
    #expect(next.timeIntervalSince(rhythm.current.end) < 0.1)
    #expect(try checkedRhythm(desk.engine, at: next).current != rhythm.current)
}

@Test func `a digit that changes before the break is due is drawn first`() throws {
    let desk = try runningOn25(minutes: 120)
    let now = at(10) - 0.5
    let status = try desk.engine.settle(at: now)
    let rhythm = try checkedRhythm(desk.engine, at: now)

    let next = MenuBarLabel.nextRedraw(status: status, rhythm: rhythm, untrackedSince: nine, after: now)

    #expect(next > at(10))
    #expect(next < at(10) + 0.1)
}

@Test func `a rhythm's moment that passed, or a break that runs, leaves the next draw to the digits`() throws {
    let desk = try runningOn25(minutes: 120)
    let early = try checkedRhythm(desk.engine, at: at(10))
    let status = working(left: 95 * 60 - 30)
    let after = at(25.5)
    #expect(MenuBarLabel.nextRedraw(status: status, rhythm: early, untrackedSince: nine, after: after)
        == MenuBarLabel.nextRedraw(status: status, untrackedSince: nine, after: after))

    try desk.engine.startBreak(minutes: 5, at: at(27))
    let resting = try desk.engine.settle(at: at(28))
    let rhythm = try checkedRhythm(desk.engine, at: at(28))
    #expect(MenuBarLabel.nextRedraw(status: resting, rhythm: rhythm, untrackedSince: nine, after: at(28))
        == MenuBarLabel.nextRedraw(status: resting, untrackedSince: nine, after: at(28)))
}

@Test func `while paused the rhythm asks for no draw of its own`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.pause(at: at(24.9))
    let status = try desk.engine.settle(at: at(25))
    let rhythm = try checkedRhythm(desk.engine, at: at(25))

    #expect(MenuBarLabel.nextRedraw(status: status, rhythm: rhythm, untrackedSince: nine, after: at(25)) == at(26))
}

// MARK: - The item during a planned break

@Test func `during a planned break the item shows what it shows during one taken by hand`() throws {
    let planned = try sample(.rhythmBreak)
    let byHand = try sample(.onBreak)

    let labels = try [planned, byHand].map { engine, _ in
        try MenuBarLabel(
            status: engine.settle(at: nine), workspace: engine.runningWorkspace(), untrackedSince: nine, at: nine,
        )
    }

    #expect(labels == [.onBreak(time: "4:12"), .onBreak(time: "4:12")])
}

// MARK: - The scenarios

@Test(arguments: [
    ("rhythm", TimerScenario.rhythm), ("rhythm-due", .rhythmDue), ("rhythm-break", .rhythmBreak),
    ("rhythm-short", .rhythmShort), ("rhythm-wait", .rhythmWait),
] as [(String, TimerScenario)])
func `each rhythm scenario is named by its launch argument`(raw: String, scenario: TimerScenario) {
    #expect(TimerScenario(launchArgument: raw) == scenario)
    #expect(TimerScenario(launchArgument: raw.uppercased()) == nil)
}

@Test(arguments: [
    (TimerScenario.rhythm, CompactPanel.Line.breakIn("2:00", minutes: 19)),
    (.rhythmDue, .breakDue("2:00", minutes: 5)),
    (.rhythmBreak, .rhythmBreak(minutes: 5, returnTo: "Acme")),
    (.rhythmShort, .breakIn("0:06", minutes: 1)),
    (.rhythmWait, .breakIn("0:06", minutes: 1)),
] as [(TimerScenario, CompactPanel.Line)])
func `each rhythm scenario puts the sample panel into its state`(
    scenario: TimerScenario, line: CompactPanel.Line,
) throws {
    let (engine, context) = try sample(scenario)

    #expect(try panel(engine, at: nine).line == line)
    #expect(try panel(engine, at: nine).name == "Acme")
    try expectHistoryKeepsRules(context)
}

@Test func `the rhythm scenario shows its taken break and the two planned ones`() throws {
    let (engine, context) = try sample(.rhythm)

    let gaps = try panel(engine, at: nine).gaps

    #expect(gaps.map { Int(($0.lowerBound * 120).rounded()) } == [25, 55, 85])
    #expect(gaps.map { Int(($0.upperBound * 120).rounded()) } == [30, 60, 90])
    let block = try #require(try engine.runningBlock())
    #expect(try entries(context).filter { $0.block === block }.map(\.kind) == [.work, .break, .work])
}

@Test(arguments: TimerScenario.allCases.filter { !$0.rawValue.hasPrefix("rhythm") && $0 != .idleBreak })
func `every other scenario runs without a rhythm`(scenario: TimerScenario) throws {
    let (engine, _) = try sample(scenario)

    #expect(try engine.rhythm(at: nine) == nil)
}

// MARK: - A whole block, tick by tick

/// What the timer announces over a block, and when, in seconds after nine.
private struct Heard: Equatable {
    let kind: AlertKind
    let second: Int
}

/// What the last settle reported, and when.
private struct Settled {
    let status: TimerStatus
    let rhythm: FocusRhythm?
    let time: Date
}

/// Drives `engine` as the app does, from one redraw to the next, until no
/// block runs, and returns every alert that became due. `atEachTick` may act,
/// and returns whether it did: an action forgets the last settle.
private func listen(
    to engine: TimerEngine, atEachTick act: (Date, TimerStatus, FocusRhythm?) throws -> Bool,
) throws -> [Heard] {
    var heard: [Heard] = []
    var last: Settled?
    var now = nine
    for _ in 0 ..< 10000 {
        let status = try engine.settle(at: now)
        let rhythm = try engine.rhythm(at: now)
        if let last, let kind = AlertKind.due(
            from: last.status, rhythm: last.rhythm, at: last.time, to: status, at: now,
        ) {
            heard.append(Heard(kind: kind, second: Int(now.timeIntervalSince(nine))))
        }
        guard status.state != .idle else { return heard }
        if try act(now, status, rhythm) {
            last = nil
            now += 0.01
            continue
        }
        last = Settled(status: status, rhythm: rhythm, time: now)
        now = MenuBarLabel.nextRedraw(status: status, rhythm: rhythm, untrackedSince: nine, after: now)
    }
    return heard
}

@Test func `with every break ignored the short scenario announces two focus ends and the block's end`() throws {
    let (engine, context) = try sample(.rhythmShort)

    let heard = try listen(to: engine) { _, _, _ in false }

    #expect(heard == [
        Heard(kind: .focusEnd, second: 60), Heard(kind: .focusEnd, second: 180), Heard(kind: .blockEnd, second: 360),
    ])
    #expect(try entries(context).filter { $0.start >= nine }.map(\.kind) == [.work])
}

@Test func `with every due break taken the short scenario announces each focus end and each break end`() throws {
    let (engine, context) = try sample(.rhythmShort)

    let heard = try listen(to: engine) { now, _, rhythm in
        guard let rhythm, rhythm.isBreakDue, let minutes = rhythm.nextBreakMinutes else { return false }
        try engine.startBreak(minutes: minutes, at: now)
        return true
    }

    #expect(heard == [
        Heard(kind: .focusEnd, second: 60), Heard(kind: .breakEnd, second: 120),
        Heard(kind: .focusEnd, second: 180), Heard(kind: .breakEnd, second: 240), Heard(kind: .blockEnd, second: 360),
    ])
    #expect(try entries(context).filter { $0.start >= nine }.map(\.kind) == [.work, .break, .work, .break, .work])
}

@Test func `the waiting scenario stands still after each break until Resume`() throws {
    let (engine, _) = try sample(.rhythmWait)
    var resumed: [Int] = []

    let heard = try listen(to: engine) { now, status, rhythm in
        if status.state == .paused {
            try engine.resume(at: now)
            resumed.append(Int(now.timeIntervalSince(nine)))
            return true
        }
        guard let rhythm, rhythm.isBreakDue, let minutes = rhythm.nextBreakMinutes else { return false }
        try engine.startBreak(minutes: minutes, at: now)
        return true
    }

    #expect(heard.map(\.kind) == [.focusEnd, .breakEnd, .focusEnd, .breakEnd, .blockEnd])
    #expect(heard.map(\.second) == [60, 120, 180, 240, 360])
    #expect(resumed == [120, 240])
}

@Test func `left alone after its first break the waiting scenario stays paused and its block never ends`() throws {
    let (engine, _) = try sample(.rhythmWait)
    _ = try engine.settle(at: at(1))
    try engine.startBreak(minutes: 1, at: at(1))

    #expect(try engine.settle(at: at(60)).state == .paused)
    #expect(try engine.settle(at: at(60)).blockTimeLeft == 4 * 60)
    #expect(try panel(engine, at: at(60)).line == .paused)
}
