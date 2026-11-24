@testable import DontBurnCore
import Foundation
import Testing

// With the clock moved back, a moment before the block's latest stored time
// (its planned start, or an entry's start or end) is read as that time, so the
// rhythm never runs backwards. Each check also holds the plan's end against
// the engine's planned end at the same moment.

/// The rhythm of a 60-minute 25/5 block from nine, with nothing taken yet.
private let untouched = FocusRhythm(
    current: focus(0, 25), isBreakDue: false, nextBreak: shortBreak(25, 30), nextBreakMinutes: 5,
    roundsDone: 0, plan: [focus(0, 25), shortBreak(25, 30), focus(30, 60)],
)

@Test(arguments: [-60.0, -5])
func `with the clock moved back before the block's start the rhythm reads as at the block's start`(
    minute: Double,
) throws {
    let desk = try runningOn25()

    #expect(try checkedRhythm(desk.engine, at: at(minute)) == untouched)
    #expect(try desk.engine.settle(at: at(minute)).state == .working)
    #expect(try desk.engine.settle(at: at(minute)).plannedEnd == at(60))
}

@Test func `with the clock moved back behind work after a break the rhythm reads as when that work began`() throws {
    let desk = try runningOn25()
    try desk.engine.startBreak(minutes: 15, at: at(10))
    let afterBreak = FocusRhythm(
        current: focus(25, 50), isBreakDue: false, nextBreak: shortBreak(50, 55), nextBreakMinutes: 5,
        roundsDone: 1, plan: [focus(25, 50), shortBreak(50, 55), focus(55, 60)],
    )
    #expect(try checkedRhythm(desk.engine, at: at(26)) == afterBreak)

    #expect(try checkedRhythm(desk.engine, at: at(12)) == afterBreak)
    #expect(try desk.engine.settle(at: at(12)).state == .working)
    #expect(try desk.engine.settle(at: at(12)).plannedEnd == at(60))
}

@Test func `with the clock moved back during a pause the rhythm reads as when the pause began`() throws {
    let desk = try runningOn25()
    try desk.engine.pause(at: at(20))

    #expect(try checkedRhythm(desk.engine, at: at(10)) == untouched)
    #expect(try desk.engine.settle(at: at(10)).state == .paused)
    #expect(try desk.engine.settle(at: at(10)).plannedEnd == at(60))
    #expect(try checkedRhythm(desk.engine, at: at(20)) == untouched)
}

@Test func `with the clock moved back before a break began the rhythm reads as at the break's start`() throws {
    let desk = try runningOn25()
    try desk.engine.startBreak(minutes: 5, at: at(10))
    let onBreak = FocusRhythm(
        current: shortBreak(10, 15), isBreakDue: false, nextBreak: shortBreak(40, 45), nextBreakMinutes: 5,
        roundsDone: 1, plan: [shortBreak(10, 15), focus(15, 40), shortBreak(40, 45), focus(45, 60)],
    )

    #expect(try checkedRhythm(desk.engine, at: at(8)) == onBreak)
    #expect(try desk.engine.settle(at: at(8)).state == .onBreak)
    #expect(try desk.engine.settle(at: at(8)).plannedEnd == at(60))
    #expect(try checkedRhythm(desk.engine, at: at(10)) == onBreak)
}
