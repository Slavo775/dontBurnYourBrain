@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// The rhythm is derived from the stored block and entries alone, so a new
// engine, or a store reopened from disk, gives the same answers in every state.

/// A state of a block's rhythm: how to reach it, the moment it is asked about,
/// and what the engine says then.
enum RhythmState: String, CaseIterable, Sendable {
    case inFocus
    case breakDue
    case onPlannedBreak
    case skipped
    case paused
    case pausedAfterWaiting

    /// The preset Acme follows. Only the waiting state waits for Resume.
    func preset() -> FocusPreset {
        self == .pausedAfterWaiting
            ? FocusPreset(name: "50/10", focusMinutes: 50, breakMinutes: 10, resumesAfterBreak: false)
            : FocusPreset(
                name: "25/5", focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 15, roundsBeforeLongBreak: 4,
            )
    }

    /// Starts Acme's block at nine and stops before ``moment``, so a restarted
    /// engine does the settling that is due by then.
    func reach(with engine: TimerEngine, starting acme: Workspace) throws {
        try engine.start(acme, minutes: self == .pausedAfterWaiting ? 120 : 60, at: nine)
        switch self {
        case .inFocus, .breakDue, .skipped: break
        case .onPlannedBreak: try engine.startBreak(minutes: 5, at: at(25))
        case .paused: try engine.pause(at: at(10))
        case .pausedAfterWaiting: try engine.startBreak(minutes: 10, at: at(50))
        }
    }

    /// The moment the state is asked about.
    var moment: Date {
        switch self {
        case .inFocus: at(10)
        case .breakDue, .onPlannedBreak: at(27)
        case .skipped: at(31)
        case .paused: at(20)
        case .pausedAfterWaiting: at(70)
        }
    }

    /// The rhythm at ``moment``.
    var rhythm: FocusRhythm {
        switch self {
        case .inFocus:
            FocusRhythm(
                current: focus(0, 25), isBreakDue: false, nextBreak: shortBreak(25, 30),
                nextBreakMinutes: 5, roundsDone: 0,
                plan: [focus(0, 25), shortBreak(25, 30), focus(30, 60)],
            )
        case .breakDue:
            FocusRhythm(
                current: shortBreak(25, 30), isBreakDue: true, nextBreak: shortBreak(25, 30), nextBreakMinutes: 5,
                roundsDone: 1, plan: [shortBreak(25, 30), focus(30, 60)],
            )
        case .onPlannedBreak:
            FocusRhythm(
                current: shortBreak(25, 30), isBreakDue: false, nextBreak: nil, nextBreakMinutes: nil,
                roundsDone: 1, plan: [shortBreak(25, 30), focus(30, 60)],
            )
        case .skipped:
            FocusRhythm(
                current: focus(30, 60), isBreakDue: false, nextBreak: nil, nextBreakMinutes: nil,
                roundsDone: 1, plan: [focus(30, 60)],
            )
        case .paused:
            FocusRhythm(
                current: focus(0, 35), isBreakDue: false, nextBreak: shortBreak(35, 40),
                nextBreakMinutes: 5, roundsDone: 0,
                plan: [focus(0, 35), shortBreak(35, 40), focus(40, 70)],
            )
        case .pausedAfterWaiting:
            FocusRhythm(
                current: focus(60, 130), isBreakDue: false, nextBreak: nil,
                nextBreakMinutes: nil, roundsDone: 1, plan: [focus(60, 130)],
            )
        }
    }

    /// The timer's status at ``moment``.
    var status: TimerStatus {
        switch self {
        case .inFocus:
            TimerStatus(state: .working, plannedEnd: at(60), blockTimeLeft: 50 * 60, breakTimeLeft: nil)
        case .breakDue:
            TimerStatus(state: .working, plannedEnd: at(60), blockTimeLeft: 33 * 60, breakTimeLeft: nil)
        case .onPlannedBreak:
            TimerStatus(state: .onBreak, plannedEnd: at(60), blockTimeLeft: 33 * 60, breakTimeLeft: 3 * 60)
        case .skipped:
            TimerStatus(state: .working, plannedEnd: at(60), blockTimeLeft: 29 * 60, breakTimeLeft: nil)
        case .paused:
            TimerStatus(state: .paused, plannedEnd: at(70), blockTimeLeft: 50 * 60, breakTimeLeft: nil)
        case .pausedAfterWaiting:
            TimerStatus(state: .paused, plannedEnd: at(130), blockTimeLeft: 60 * 60, breakTimeLeft: nil)
        }
    }
}

@Test(arguments: RhythmState.allCases)
func `after a restart in each state of the rhythm a new engine on the same store gives the same answers`(
    state: RhythmState,
) throws {
    let desk = try Desk()
    try desk.acmeFollows(state.preset())
    try state.reach(with: desk.engine, starting: desk.acme)

    let (engine, context) = desk.restarted()

    #expect(try engine.rhythm(at: state.moment) == state.rhythm)
    #expect(try engine.settle(at: state.moment) == state.status)
    try expectHistoryKeepsRules(context)
}

@Test(arguments: RhythmState.allCases)
func `after a restart in each state of the rhythm a store reopened from disk gives the same answers`(
    state: RhythmState,
) throws {
    try withTemporaryFolder { folder in
        do {
            let context = try ModelContext(ModelStore.onDisk(in: folder.url))
            let acme = Workspace(name: "Acme", color: .teal)
            let preset = state.preset()
            context.insert(acme)
            context.insert(preset)
            acme.focusPreset = preset
            try context.save()
            try state.reach(with: TimerEngine(context: context), starting: acme)
        }

        let context = try ModelContext(ModelStore.onDisk(in: folder.url))
        let engine = TimerEngine(context: context)

        #expect(try engine.rhythm(at: state.moment) == state.rhythm)
        #expect(try engine.settle(at: state.moment) == state.status)
        let block = try #require(try blocks(context).first)
        #expect(block.focusPreset?.name == state.preset().name)
        #expect(block.resumesAfterBreak == (state != .pausedAfterWaiting))
        try expectHistoryKeepsRules(context)
    }
}
