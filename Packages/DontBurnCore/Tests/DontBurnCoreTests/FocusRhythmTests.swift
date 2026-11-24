@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// Card #57: a block with a preset follows a rhythm of focus intervals and
// breaks. A due break only tells, the block's end comes first, and the plan is
// derived from the block's own copy of its rhythm and from its entries.

// MARK: - The seeded presets from start to planned end

/// The plan of a block from nine to its end, for each seeded preset: 150 minutes on 25/5 and 120 on 50/10.
@Test(arguments: [
    ("25/5", [
        focus(0, 25), shortBreak(25, 30), focus(30, 55), shortBreak(55, 60), focus(60, 85), shortBreak(85, 90),
        focus(90, 115), longBreak(115, 130), focus(130, 150),
    ]),
    ("50/10", [focus(0, 50), shortBreak(50, 60), focus(60, 120)]),
] as [(String, [FocusInterval])])
func `a block on each seeded preset follows its plan from start to planned end when every due break is taken`(
    name: String, plan: [FocusInterval],
) throws {
    let end = try #require(plan.last?.end)
    let minutes = Int(end.timeIntervalSince(nine) / 60)
    let desk = try Desk()
    try desk.acmeFollowsSeeded(name)
    try desk.engine.start(desk.acme, minutes: minutes, at: nine)
    #expect(try desk.engine.rhythm(at: nine)?.plan == plan)

    var minute = 0.0
    var rounds = 0
    while let rhythm = try desk.engine.rhythm(at: at(minute)) {
        expectPlanKeepsRules(rhythm, endsAt: end)
        #expect(plan.contains(rhythm.current), "at minute \(minute)")
        if rhythm.isBreakDue, let length = rhythm.nextBreakMinutes {
            try desk.engine.startBreak(minutes: length, at: at(minute))
        }
        rounds = rhythm.roundsDone
        minute += 1
    }

    #expect(minute == Double(minutes))
    #expect(rounds == plan.count { $0.kind != .focus })
    let history = try entries(desk.context)
    #expect(history.map(\.kind) == plan.map { $0.kind == .focus ? .work : .break })
    #expect(history.map(\.start) == plan.map(\.start))
    #expect(history.map(\.end) == plan.map(\.end))
    #expect(try blocks(desk.context).map(\.state) == [.done])
    try expectHistoryKeepsRules(desk.context)
}

@Test(arguments: [0.0, 10, 24.9])
func `a 60 minute block on 25/5 is focus to minute 25, then its one short break, then focus to the end`(
    minute: Double,
) throws {
    let desk = try runningOn25()

    #expect(try checkedRhythm(desk.engine, at: at(minute)) == FocusRhythm(
        current: focus(0, 25), isBreakDue: false, nextBreak: shortBreak(25, 30), nextBreakMinutes: 5,
        roundsDone: 0, plan: [focus(0, 25), shortBreak(25, 30), focus(30, 60)],
    ))
}

// MARK: - A due break only tells

@Test(arguments: [25.0, 27, 29.9])
func `when a focus interval's minutes are done the planned break is due, and the engine starts nothing`(
    minute: Double,
) throws {
    let desk = try runningOn25()

    #expect(try checkedRhythm(desk.engine, at: at(minute)) == FocusRhythm(
        current: shortBreak(25, 30), isBreakDue: true, nextBreak: shortBreak(25, 30), nextBreakMinutes: 5,
        roundsDone: 1, plan: [shortBreak(25, 30), focus(30, 60)],
    ))
    #expect(try desk.engine.settle(at: at(minute)).state == .working)
    #expect(try entries(desk.context).map(\.kind) == [.work])
}

@Test(arguments: [30.0, 45, 59])
func `a due break worked through is skipped after its planned length, leaves no entry, and focus starts at its end`(
    minute: Double,
) throws {
    let desk = try runningOn25()

    #expect(try checkedRhythm(desk.engine, at: at(minute)) == FocusRhythm(
        current: focus(30, 60), isBreakDue: false, nextBreak: nil, nextBreakMinutes: nil,
        roundsDone: 1, plan: [focus(30, 60)],
    ))
    let history = try entries(desk.context)
    #expect(history.map(\.kind) == [.work])
    #expect(history.first?.end == nil)
}

@Test(arguments: [5, 15, 30])
func `a break taken while one is due is the planned one, whatever its length, and focus starts when it ends`(
    minutes: Int,
) throws {
    let desk = try runningOn25(minutes: 120)
    let length = Double(minutes)
    try desk.engine.startBreak(minutes: minutes, at: at(27))

    let during = try checkedRhythm(desk.engine, at: at(28))
    #expect(during.current == shortBreak(27, 27 + length))
    #expect(!during.isBreakDue)
    #expect(during.roundsDone == 1)
    #expect(during.nextBreak == shortBreak(52 + length, 57 + length))
    #expect(during.nextBreakMinutes == 5)
    let after = try checkedRhythm(desk.engine, at: at(28 + length))
    #expect(after.current == focus(27 + length, 52 + length))
    #expect(after.roundsDone == 1)
    #expect(after.nextBreak == shortBreak(52 + length, 57 + length))
    #expect(try entries(desk.context).map(\.kind) == [.work, .break, .work])
}

// MARK: - A break taken by hand

@Test func `a break taken mid focus interval ends the round, and the next focus interval starts when it ends`() throws {
    let desk = try runningOn25()
    try desk.engine.startBreak(minutes: 15, at: at(10))

    #expect(try checkedRhythm(desk.engine, at: at(12)) == FocusRhythm(
        current: shortBreak(10, 25), isBreakDue: false, nextBreak: shortBreak(50, 55), nextBreakMinutes: 5,
        roundsDone: 1, plan: [shortBreak(10, 25), focus(25, 50), shortBreak(50, 55), focus(55, 60)],
    ))
    #expect(try checkedRhythm(desk.engine, at: at(26)) == FocusRhythm(
        current: focus(25, 50), isBreakDue: false, nextBreak: shortBreak(50, 55), nextBreakMinutes: 5,
        roundsDone: 1, plan: [focus(25, 50), shortBreak(50, 55), focus(55, 60)],
    ))
}

@Test func `a break taken by hand and ended early by hand starts a full focus interval when it ends`() throws {
    let desk = try runningOn25()
    try desk.engine.startBreak(minutes: 15, at: at(10))
    try desk.engine.endBreak(at: at(15))

    #expect(try checkedRhythm(desk.engine, at: at(16)) == FocusRhythm(
        current: focus(15, 40), isBreakDue: false, nextBreak: shortBreak(40, 45), nextBreakMinutes: 5,
        roundsDone: 1, plan: [focus(15, 40), shortBreak(40, 45), focus(45, 60)],
    ))
}

// MARK: - Pausing

@Test func `a pause across a planned break moves the plan later, and focus keeps the work it had left`() throws {
    let desk = try runningOn25()
    try desk.engine.pause(at: at(20))

    #expect(try checkedRhythm(desk.engine, at: at(30)) == FocusRhythm(
        current: focus(0, 35), isBreakDue: false, nextBreak: shortBreak(35, 40), nextBreakMinutes: 5,
        roundsDone: 0, plan: [focus(0, 35), shortBreak(35, 40), focus(40, 70)],
    ))

    try desk.engine.resume(at: at(40))
    #expect(try checkedRhythm(desk.engine, at: at(44)) == FocusRhythm(
        current: focus(0, 45), isBreakDue: false, nextBreak: shortBreak(45, 50), nextBreakMinutes: 5,
        roundsDone: 0, plan: [focus(0, 45), shortBreak(45, 50), focus(50, 80)],
    ))
    #expect(try checkedRhythm(desk.engine, at: at(45)) == FocusRhythm(
        current: shortBreak(45, 50), isBreakDue: true, nextBreak: shortBreak(45, 50), nextBreakMinutes: 5,
        roundsDone: 1, plan: [shortBreak(45, 50), focus(50, 80)],
    ))
}

@Test func `a due break's window stands still while paused, and is skipped only after its length of work`() throws {
    let desk = try runningOn25()
    try desk.engine.pause(at: at(27))

    #expect(try checkedRhythm(desk.engine, at: at(50)) == FocusRhythm(
        current: shortBreak(25, 53), isBreakDue: true, nextBreak: shortBreak(25, 53), nextBreakMinutes: 5,
        roundsDone: 1, plan: [shortBreak(25, 53), focus(53, 83)],
    ))

    try desk.engine.resume(at: at(50))
    #expect(try checkedRhythm(desk.engine, at: at(52.9)).isBreakDue)
    #expect(try checkedRhythm(desk.engine, at: at(53)) == FocusRhythm(
        current: focus(53, 83), isBreakDue: false, nextBreak: nil, nextBreakMinutes: nil,
        roundsDone: 1, plan: [focus(53, 83)],
    ))
    #expect(try entries(desk.context).map(\.kind) == [.work, .work])
}

@Test func `pausing on a break ends the break, and Resume starts a full focus interval`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.startBreak(minutes: 5, at: at(25))
    try desk.engine.pause(at: at(27))

    #expect(try entries(desk.context).map(\.end) == [at(25), at(27)])
    let paused = try checkedRhythm(desk.engine, at: at(30))
    #expect(paused.current.kind == .focus)
    #expect(!paused.isBreakDue)
    #expect(paused.roundsDone == 1)

    try desk.engine.resume(at: at(40))
    #expect(try checkedRhythm(desk.engine, at: at(40)).nextBreak == shortBreak(65, 70))
    #expect(try checkedRhythm(desk.engine, at: at(64.9)).isBreakDue == false)
    #expect(try checkedRhythm(desk.engine, at: at(65)).isBreakDue)
}

// MARK: - Extending

@Test func `+15 recomputes the plan and brings back a break the block's end had left out`() throws {
    let desk = try runningOn25()
    #expect(try checkedRhythm(desk.engine, at: at(40)).plan == [focus(30, 60)])

    try desk.engine.extend(by: 15, at: at(40))

    #expect(try checkedRhythm(desk.engine, at: at(40)) == FocusRhythm(
        current: focus(30, 55), isBreakDue: false, nextBreak: shortBreak(55, 60), nextBreakMinutes: 5,
        roundsDone: 1, plan: [focus(30, 55), shortBreak(55, 60), focus(60, 75)],
    ))
}

@Test func `+15 while a break is due keeps its window and plans the rest of the longer block`() throws {
    let desk = try runningOn25()
    try desk.engine.extend(by: 15, at: at(27))

    #expect(try checkedRhythm(desk.engine, at: at(27)) == FocusRhythm(
        current: shortBreak(25, 30), isBreakDue: true, nextBreak: shortBreak(25, 30), nextBreakMinutes: 5,
        roundsDone: 1, plan: [shortBreak(25, 30), focus(30, 55), shortBreak(55, 60), focus(60, 75)],
    ))
}

@Test func `+15 on a planned break moves its end and the block's end, and the work after it stays the same`() throws {
    let desk = try runningOn25()
    try desk.engine.startBreak(minutes: 5, at: at(25))
    #expect(try checkedRhythm(desk.engine, at: at(27)).plan == [shortBreak(25, 30), focus(30, 60)])

    try desk.engine.extend(by: 15, at: at(27))

    let rhythm = try checkedRhythm(desk.engine, at: at(28))
    #expect(rhythm == FocusRhythm(
        current: shortBreak(25, 45), isBreakDue: false, nextBreak: nil, nextBreakMinutes: nil,
        roundsDone: 1, plan: [shortBreak(25, 45), focus(45, 75)],
    ))
    let status = try desk.engine.settle(at: at(28))
    #expect(status == TimerStatus(state: .onBreak, plannedEnd: at(75), blockTimeLeft: 47 * 60, breakTimeLeft: 17 * 60))
    #expect(rhythm.current.end == at(28).addingTimeInterval(status.breakTimeLeft ?? 0))
    #expect(try checkedRhythm(desk.engine, at: at(46)).current == focus(45, 75))
}

// MARK: - The block's end comes first

@Test(arguments: [
    (10, [focus(0, 10)]),
    (30, [focus(0, 30)]),
    (55, [focus(0, 25), shortBreak(25, 30), focus(30, 55)]),
    (60, [focus(0, 25), shortBreak(25, 30), focus(30, 60)]),
    (61, [focus(0, 25), shortBreak(25, 30), focus(30, 55), shortBreak(55, 60), focus(60, 61)]),
] as [(Int, [FocusInterval])])
func `a planned break that would end at or after the block's end is left out, and focus runs on to the end`(
    minutes: Int, plan: [FocusInterval],
) throws {
    let desk = try runningOn25(minutes: minutes)

    let rhythm = try checkedRhythm(desk.engine, at: nine)

    #expect(rhythm.plan == plan)
    #expect(rhythm.nextBreak == plan.first { $0.kind != .focus })
}

@Test func `a long break that does not fit before the block's end is left out, not replaced by a short one`() throws {
    let desk = try runningOn25(minutes: 125)

    #expect(try checkedRhythm(desk.engine, at: nine).plan == [
        focus(0, 25), shortBreak(25, 30), focus(30, 55), shortBreak(55, 60), focus(60, 85), shortBreak(85, 90),
        focus(90, 125),
    ])
}

// MARK: - Rounds

@Test(arguments: [(0.0, 0), (24.9, 0), (25, 1), (29.9, 1), (30, 1), (54.9, 1), (59.9, 1)] as [(Double, Int)])
func `rounds count each break that came due, a skipped one once, and none for a break the block's end left out`(
    minute: Double, rounds: Int,
) throws {
    let desk = try runningOn25()

    #expect(try checkedRhythm(desk.engine, at: at(minute)).roundsDone == rounds)
}

@Test func `breaks taken by hand count toward the long break, so the fourth is the long one either way`() throws {
    let desk = try runningOn25(minutes: 120)
    for minute in [10.0, 20, 30] {
        try desk.engine.startBreak(minutes: 5, at: at(minute))
    }

    let rhythm = try checkedRhythm(desk.engine, at: at(36))

    #expect(rhythm.roundsDone == 3)
    #expect(rhythm.current == focus(35, 60))
    #expect(rhythm.nextBreak == longBreak(60, 75))
    #expect(rhythm.nextBreakMinutes == 15)
}
