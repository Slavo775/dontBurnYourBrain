@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

extension Desk {
    /// Seeds the presets the app comes with, gives Acme the one named `name`, and returns it.
    @discardableResult
    func acmeFollowsSeeded(_ name: String) throws -> FocusPreset {
        try FocusPreset.seedDefaults(into: context)
        let preset = try #require(try context.fetch(FetchDescriptor<FocusPreset>()).first { $0.name == name })
        acme.focusPreset = preset
        try context.save()
        return preset
    }

    /// Gives Acme `preset`, which is inserted first.
    func acmeFollows(_ preset: FocusPreset) throws {
        context.insert(preset)
        acme.focusPreset = preset
        try context.save()
    }
}

/// 25/5 that waits for Resume after every break.
func waitingPreset(focus: Int = 25, break breakMinutes: Int = 5) -> FocusPreset {
    FocusPreset(name: "Wait", focusMinutes: focus, breakMinutes: breakMinutes, resumesAfterBreak: false)
}

/// A focus interval from `start` to `end` minutes after nine.
func focus(_ start: Double, _ end: Double) -> FocusInterval {
    FocusInterval(kind: .focus, start: at(start), end: at(end))
}

/// A short break from `start` to `end` minutes after nine.
func shortBreak(_ start: Double, _ end: Double) -> FocusInterval {
    FocusInterval(kind: .shortBreak, start: at(start), end: at(end))
}

/// A long break from `start` to `end` minutes after nine.
func longBreak(_ start: Double, _ end: Double) -> FocusInterval {
    FocusInterval(kind: .longBreak, start: at(start), end: at(end))
}

/// Checks the rules every plan keeps: it starts with the current interval,
/// runs without gaps, holds no empty interval, and ends exactly at the block's
/// planned end.
func expectPlanKeepsRules(
    _ rhythm: FocusRhythm, endsAt plannedEnd: Date?, sourceLocation: SourceLocation = #_sourceLocation,
) {
    #expect(rhythm.plan.first == rhythm.current, "the plan does not start with the current interval",
            sourceLocation: sourceLocation)
    #expect(rhythm.plan.last?.end == plannedEnd, "the plan does not end at the block's end",
            sourceLocation: sourceLocation)
    for interval in rhythm.plan {
        #expect(interval.start < interval.end, "an empty interval", sourceLocation: sourceLocation)
    }
    for (earlier, later) in zip(rhythm.plan, rhythm.plan.dropFirst()) {
        #expect(earlier.end == later.start, "a gap in the plan", sourceLocation: sourceLocation)
    }
}

/// The rhythm at `now`, after checking that its plan keeps the rules against the engine's own status.
func checkedRhythm(
    _ engine: TimerEngine, at now: Date, sourceLocation: SourceLocation = #_sourceLocation,
) throws -> FocusRhythm {
    let rhythm = try #require(try engine.rhythm(at: now), sourceLocation: sourceLocation)
    try expectPlanKeepsRules(rhythm, endsAt: engine.settle(at: now).plannedEnd, sourceLocation: sourceLocation)
    return rhythm
}

/// The block's copy of its rhythm: focus, short break, long break, and the rounds before the long one.
func rhythmCopy(of block: TimeBlock) -> [Int] {
    [block.focusMinutes, block.breakMinutes, block.longBreakMinutes, block.roundsBeforeLongBreak]
}

/// A desk whose Acme follows the seeded 25/5 and runs a block of `minutes` from nine.
func runningOn25(minutes: Int = 60) throws -> Desk {
    let desk = try Desk()
    try desk.acmeFollowsSeeded("25/5")
    try desk.engine.start(desk.acme, minutes: minutes, at: nine)
    return desk
}
