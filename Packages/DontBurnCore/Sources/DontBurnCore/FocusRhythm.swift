import Foundation
import SwiftData

/// One stretch of a block's plan: focus, or a break.
public struct FocusInterval: Equatable, Sendable {
    /// What a stretch of the plan is for.
    public enum Kind: Equatable, Sendable {
        /// Focus: work, or a meeting.
        case focus
        /// A short break.
        case shortBreak
        /// The long break, which comes every so many breaks.
        case longBreak
    }

    /// What the stretch is for.
    public let kind: Kind
    /// When the stretch began, or is planned to begin.
    public let start: Date
    /// When the stretch is planned to end. A pause moves it later.
    public let end: Date
}

/// Where a block with a rhythm stands at one moment, and its plan from there
/// to the block's end.
///
/// Derived, never stored, like the block's planned end: from the block's own
/// copy of its rhythm and from its entries. The rhythm moves only while an
/// entry runs, so a pause holds both the work a focus interval has left and
/// the window of a due break, and moves the plan later.
///
/// - A focus interval ends when its minutes of work are done, or when a break
///   is taken by hand. Either ends the round. A break taken by hand lasts as
///   long as he chose, and the next focus interval starts when it ends.
/// - A planned break that is due only tells. Taking a break then takes it.
///   When he keeps working for its planned length instead, it is skipped: it
///   leaves no entry, and the next focus interval starts there.
/// - Every ``SchemaV2/TimeBlock/roundsBeforeLongBreak``th break is the long one.
/// - A planned break that would end at or after the block's end is left out,
///   so the last focus interval runs on to the end. Since the plan is derived,
///   an extension can bring such a break back.
public struct FocusRhythm: Equatable, Sendable {
    /// The interval running now: focus, the break being taken, or the planned
    /// break that is due while he keeps working or is paused.
    public let current: FocusInterval
    /// Whether a planned break is due and no break is being taken.
    public let isBreakDue: Bool
    /// The planned break that is due, or else the next one, or `nil` when none
    /// fits before the block's end. Never the break being taken.
    public let nextBreak: FocusInterval?
    /// The planned length of ``nextBreak``, in minutes: the one to pass to
    /// ``TimerEngine/startBreak(minutes:at:)``.
    public let nextBreakMinutes: Int?
    /// How many rounds are done: one for each break taken or due, skipped ones included.
    public let roundsDone: Int
    /// The plan from ``current`` to the block's end, earliest first and without
    /// gaps. What follows ``current`` assumes no pause, and that every planned
    /// break is taken at its planned length and ends by itself.
    public let plan: [FocusInterval]
}

extension FocusRhythm {
    /// The rhythm of `block` at `now`, when the block ends at `plannedEnd`, or
    /// `nil` when the block has no rhythm.
    init?(of block: TimeBlock, plannedEnd: Date, at now: Date) {
        guard block.hasRhythm else { return nil }
        var walk = RhythmWalk(block)
        let entries = (block.entries ?? []).sorted { $0.start < $1.start }
        var lastEnd = block.plannedStart
        for entry in entries {
            let start = max(entry.start, lastEnd)
            let end = entry.end ?? max(now, start)
            if entry.kind == .break {
                walk.takeBreak(from: start, to: end, ends: entry.end != nil)
            } else {
                walk.work(for: end.timeIntervalSince(start), from: start)
            }
            lastEnd = max(lastEnd, end)
        }

        let isBreakDue = if case .due = walk.phase {
            true
        } else {
            false
        }
        let roundsDone = walk.rounds
        let open = entries.last { $0.end == nil }
        walk.isRecording = true
        var from = now
        if let open, open.kind == .break {
            let planned = open.plannedMinutes.map { open.start.addingTimeInterval(TimeInterval($0) * 60) }
            from = max(now, min(planned ?? plannedEnd, plannedEnd))
            walk.used += from.timeIntervalSince(now)
            walk.enter(.focus, for: walk.focus, at: from)
        }
        walk.work(for: plannedEnd.timeIntervalSince(from), from: from)
        // Closes the last stretch at the block's end, so the plan ends exactly there.
        walk.enter(.focus, for: 0, at: plannedEnd)

        guard let current = walk.plan.first else { return nil }
        let upcoming = open?.kind == .break ? walk.plan.dropFirst() : walk.plan[...]
        let nextBreak = upcoming.first { $0.kind != .focus }
        self.current = current
        self.isBreakDue = isBreakDue
        self.nextBreak = nextBreak
        nextBreakMinutes = nextBreak.map { $0.kind == .longBreak ? block.longBreakMinutes : block.breakMinutes }
        self.roundsDone = roundsDone
        plan = walk.plan
    }
}

/// Runs a block's time through its rhythm. Lengths are seconds of the block's
/// own time, which stands still while the block is paused.
private struct RhythmWalk {
    enum Phase {
        case focus
        /// A planned break is due and he keeps working.
        case due(FocusInterval.Kind)
        /// A break entry runs.
        case onBreak(FocusInterval.Kind)

        var kind: FocusInterval.Kind {
            switch self {
            case .focus: .focus
            case let .due(kind), let .onBreak(kind): kind
            }
        }
    }

    // ponytail: a cap, so an absurd block length cannot hang the app. Past it,
    // the last interval runs on to the block's end.
    /// The most intervals the walk records before the last one.
    static let planLimit = 1000

    let focus: TimeInterval
    let shortBreak: TimeInterval
    let longBreak: TimeInterval
    let roundsBeforeLongBreak: Int
    let length: TimeInterval

    var phase = Phase.focus
    /// The block time left in the running stretch.
    var left: TimeInterval
    var phaseStart: Date
    /// The block time used so far, breaks included.
    var used: TimeInterval = 0
    var rounds = 0
    /// Whether finished stretches go into ``plan``.
    var isRecording = false
    var plan: [FocusInterval] = []

    init(_ block: TimeBlock) {
        focus = TimeInterval(block.focusMinutes) * 60
        shortBreak = TimeInterval(block.breakMinutes) * 60
        longBreak = TimeInterval(block.longBreakMinutes) * 60
        roundsBeforeLongBreak = block.roundsBeforeLongBreak
        length = TimeInterval(block.plannedMinutes) * 60
        left = focus
        phaseStart = block.plannedStart
    }

    /// Counts `duration` of work or a meeting, from `start`.
    mutating func work(for duration: TimeInterval, from start: Date) {
        var rest = duration
        var wall = start
        while rest > 0, !isRecording || plan.count < Self.planLimit {
            let step = min(rest, left)
            rest -= step
            left -= step
            used += step
            wall = wall.addingTimeInterval(step)
            guard left <= 0 else { continue }
            switch phase {
            case .focus:
                let kind = breakKind(rounds + 1)
                let length = kind == .longBreak ? longBreak : shortBreak
                if used + length < self.length {
                    rounds += 1
                    enter(.due(kind), for: length, at: wall)
                } else {
                    // The block's end comes first, so this focus interval runs on to it.
                    left = .infinity
                }
            case .due, .onBreak:
                enter(.focus, for: focus, at: wall)
            }
        }
    }

    /// Counts a break entry from `start` to `end`, and when it `ends`, starts
    /// the next focus interval there.
    mutating func takeBreak(from start: Date, to end: Date, ends: Bool) {
        if case .focus = phase {
            rounds += 1
            enter(.onBreak(breakKind(rounds)), for: .infinity, at: start)
        } else {
            enter(.onBreak(phase.kind), for: .infinity, at: start)
        }
        used += max(0, end.timeIntervalSince(start))
        if ends {
            enter(.focus, for: focus, at: end)
        }
    }

    /// The kind of the break with `number`, counted from 1.
    func breakKind(_ number: Int) -> FocusInterval.Kind {
        let hasLong = longBreak > 0 && roundsBeforeLongBreak > 0
        return hasLong && number.isMultiple(of: roundsBeforeLongBreak) ? .longBreak : .shortBreak
    }

    /// Ends the running stretch at `time` and starts `next` there, lasting `length`.
    mutating func enter(_ next: Phase, for length: TimeInterval, at time: Date) {
        if isRecording, time > phaseStart {
            plan.append(FocusInterval(kind: phase.kind, start: phaseStart, end: time))
        }
        phase = next
        left = length
        phaseStart = time
    }
}

extension TimeBlock {
    /// Whether the block follows a rhythm: its focus intervals and its breaks both last.
    var hasRhythm: Bool {
        focusMinutes > 0 && breakMinutes > 0
    }

    /// Copies the rhythm of `preset` into the block, so a later change to the
    /// preset leaves the block alone.
    func follow(_ preset: FocusPreset) {
        focusPreset = preset
        focusMinutes = preset.focusMinutes
        breakMinutes = preset.breakMinutes
        longBreakMinutes = preset.longBreakMinutes
        roundsBeforeLongBreak = preset.roundsBeforeLongBreak
        resumesAfterBreak = preset.resumesAfterBreak
    }
}

public extension FocusPreset {
    /// The fixed identifiers of the presets the app comes with, 25/5 first.
    internal static let seededIDs = [
        UUID(uuid: (0xDE, 0x2C, 0x7E, 0x38, 0xB1, 0xF4, 0x43, 0x2D, 0x8C, 0xAA, 0xD9, 0xE7, 0x42, 0xD8, 0xF3, 0x8F)),
        UUID(uuid: (0xCD, 0xD3, 0x6B, 0x97, 0x80, 0xFA, 0x4A, 0x0B, 0xA0, 0x1C, 0xAE, 0xC5, 0xAA, 0x10, 0xB7, 0xB7)),
    ]

    /// Adds the presets the app comes with to a store that has no preset, and saves it.
    ///
    /// They are 25/5, with a long break of 15 minutes every fourth break, and
    /// 50/10 without one. Both resume by themselves after a break. Their
    /// identifiers are fixed, so two Macs that both seed make the same two
    /// presets, and sync can fold them together. No workspace is given one:
    /// "none" is no preset.
    static func seedDefaults(into context: ModelContext) throws {
        // ponytail: a store whose presets were all deleted gets these two back
        // at the next launch. Remember the seeding, such as in the defaults, if
        // that ever matters.
        guard try context.fetchCount(FetchDescriptor<FocusPreset>()) == 0 else { return }
        let presets = [
            FocusPreset(
                name: "25/5", focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 15, roundsBeforeLongBreak: 4,
            ),
            FocusPreset(name: "50/10", focusMinutes: 50, breakMinutes: 10),
        ]
        for (preset, id) in zip(presets, seededIDs) {
            preset.id = id
            context.insert(preset)
        }
        try context.save()
    }
}
