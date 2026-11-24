import Foundation
import SwiftData

/// What the compact panel shows while a block or a break runs, at one moment.
///
/// The times are already formatted as digits. The app adds the words.
public struct CompactPanel: Equatable, Sendable {
    /// The line under the countdown.
    public enum Line: Equatable, Sendable {
        /// Working: the block's planned length, such as `2:00` in "left of 2:00".
        case leftOf(String)
        /// Working: the block's planned length, and the minutes until the next
        /// planned break, 0 for less than one.
        case breakIn(String, minutes: Int)
        /// Working while a planned break is due: the block's planned length,
        /// and the planned minutes of the break.
        case breakDue(String, minutes: Int)
        /// The block is paused.
        case paused
        /// A break is running, and work continues in the named workspace after it.
        case onBreak(returnTo: String)
        /// A break of `minutes` is running in a block with a rhythm, and work
        /// continues in the named workspace after it.
        case rhythmBreak(minutes: Int, returnTo: String)
        /// A break of `minutes` is running in a block with a rhythm, and the
        /// block waits for Resume after it.
        case rhythmBreakThenPaused(minutes: Int)
        /// A break is running with no block, and nothing runs after it.
        case idleBreak
    }

    /// The running block's workspace name, in full, or empty on a break with no block.
    public let name: String
    /// The running block's workspace color, or teal, unused, on a break with no block.
    public let color: WorkspaceColor
    /// What the timer is doing: working, paused, or on a break with or without a block.
    public let state: TimerState
    /// The large part of the countdown: hours and minutes, such as `1:24`,
    /// or minutes alone, such as `24`, under an hour. On a break it counts the
    /// break, otherwise the block.
    public let clock: String
    /// The small part of the countdown, the seconds, such as `:10`.
    public let seconds: String
    /// The line under the countdown.
    public let line: Line
    /// How much of the block's planned length is used up, from 0 to 1, or
    /// of the break's on a break with no block.
    public let progress: Double
    /// The breaks in the strip as fractions of the block's planned length,
    /// from 0 to 1, earliest first: taken ones up to now, planned ones after
    /// it. Empty for a block without a rhythm and for a break with no block.
    public let gaps: [ClosedRange<Double>]
    /// The planned length of the break that is due while working, in minutes,
    /// which Break then starts at once, or `nil` while none is due.
    public let dueBreakMinutes: Int?
    /// Today's tracked time in hours and minutes, such as `0:10`.
    public let trackedToday: String

    /// What the panel shows for `status`, or `nil` when nothing runs.
    ///
    /// `block` is the running block, see ``TimerEngine/runningBlock()``, and
    /// `rhythm` where it stands in its rhythm, if it has one, see
    /// ``TimerEngine/rhythm(at:)``. `tracked` is today's tracked time, see
    /// ``trackedToday(in:now:calendar:)``. Every time is rounded down to the
    /// whole second, as in the menu bar, and those in the line to the whole minute.
    public init?(status: TimerStatus, block: TimeBlock?, rhythm: FocusRhythm? = nil, tracked: TimeInterval) {
        guard status.state != .idle, let block, let blockLeft = status.blockTimeLeft else { return nil }
        let workspace = block.workspace
        name = workspace?.name ?? ""
        color = workspace?.color ?? .teal
        state = status.state
        let shown = status.state == .onBreak ? status.breakTimeLeft ?? blockLeft : blockLeft
        (clock, seconds) = Self.split(shown)
        let planned = TimeInterval(max(0, block.plannedMinutes)) * 60
        dueBreakMinutes = status.state == .working && rhythm?.isBreakDue == true ? rhythm?.nextBreakMinutes : nil
        line = Self.line(status: status, rhythm: rhythm, planned: planned, name: name)
        progress = planned > 0 ? min(1, max(0, 1 - blockLeft / planned)) : 1
        gaps = status.plannedEnd.flatMap { rhythm?.breakFractions(of: block, plannedEnd: $0) } ?? []
        trackedToday = MenuBarLabel.hoursAndMinutes(tracked)
    }

    /// What the panel shows for `idleBreak`, the break with nothing running, at `now`.
    ///
    /// It names no workspace, and the countdown and the progress are the
    /// break's. `tracked` is today's tracked time, which the break leaves alone.
    public init(idleBreak: IdleBreak, at now: Date, tracked: TimeInterval) {
        name = ""
        color = .teal
        state = .idleBreak
        (clock, seconds) = Self.split(idleBreak.timeLeft(at: now))
        line = .idleBreak
        progress = idleBreak.progress(at: now)
        gaps = []
        dueBreakMinutes = nil
        trackedToday = MenuBarLabel.hoursAndMinutes(tracked)
    }

    /// The line under the countdown for a block of `planned` seconds in the
    /// workspace named `name`.
    ///
    /// A break that the block's end cuts off below a minute has no length to
    /// name, so its line is the one without.
    private static func line(
        status: TimerStatus, rhythm: FocusRhythm?, planned: TimeInterval, name: String,
    ) -> Line {
        let length = MenuBarLabel.hoursAndMinutes(planned)
        switch status.state {
        case .paused:
            return .paused
        case .onBreak:
            guard let rhythm, rhythm.current.minutes > 0 else { return .onBreak(returnTo: name) }
            let minutes = rhythm.current.minutes
            return rhythm.pausesAfterBreak
                ? .rhythmBreakThenPaused(minutes: minutes)
                : .rhythmBreak(minutes: minutes, returnTo: name)
        default:
            guard let rhythm, let next = rhythm.nextBreak, let minutes = rhythm.nextBreakMinutes,
                  let blockLeft = status.blockTimeLeft, let plannedEnd = status.plannedEnd
            else { return .leftOf(length) }
            if rhythm.isBreakDue {
                return .breakDue(length, minutes: minutes)
            }
            // Both count to the block's planned end, so this is the time from now to the break.
            let left = blockLeft - plannedEnd.timeIntervalSince(next.start)
            return .breakIn(length, minutes: MenuBarLabel.wholeSeconds(left) / 60)
        }
    }

    /// When the panel's seconds change next after `now`, or `nil` while
    /// nothing counts down: nothing runs, or the block is paused.
    public static func nextRedraw(status: TimerStatus, after now: Date) -> Date? {
        let left: TimeInterval? = switch status.state {
        case .idle, .paused: nil
        case .onBreak, .idleBreak: status.breakTimeLeft ?? status.blockTimeLeft
        case .working: status.blockTimeLeft
        }
        return left.map { MenuBarLabel.nextCountDown(left: $0, step: 1, after: now) }
    }

    /// Today's tracked time up to `now`: every entry's part between the start
    /// of today and `now`, running ones included.
    ///
    /// The same total as the window's Today, see ``DayLog/total``. Work and
    /// meetings always count. A break counts only when its workspace counts
    /// breaks (``SchemaV2/Workspace/breaksCount``).
    public static func trackedToday(in context: ModelContext, now: Date, calendar: Calendar) throws -> TimeInterval {
        try DayLog(day: now, in: context, now: now, calendar: calendar).total
    }

    /// `h:mm` and `:ss` from one hour on, `m` and `:ss` below it, rounded down.
    static func split(_ seconds: TimeInterval) -> (String, String) {
        let whole = MenuBarLabel.wholeSeconds(seconds)
        let hours = whole / 3600, minutes = whole % 3600 / 60
        let large = hours > 0 ? "\(hours):" + twoDigits(minutes) : "\(minutes)"
        return (large, ":" + twoDigits(whole % 60))
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }
}

/// One of the quick actions that the panel's buttons, its keys and the
/// right-click menu share. Switch and End block are separate, see
/// ``TimerEngine/switchTo(_:project:at:)`` and ``TimerEngine/end(at:)``.
public enum QuickAction: CaseIterable, Sendable {
    /// Pause while working or on a break in a block, Resume while paused.
    case pauseOrResume
    /// Take a break of the default length while working, End break on a
    /// break, with or without a block. A break of a chosen length starts
    /// through ``startBreak(minutes:with:idleBreak:at:)``.
    case breakOrEndBreak
    /// Add ``TimerEngine/defaultExtendMinutes`` to the block, and on a break
    /// to the break too, or to the break with no block alone.
    case extend

    /// Whether the action can be taken in `state`.
    ///
    /// A break cannot start while paused, because the engine starts a break
    /// only from work. On a break with no block there is nothing to pause.
    /// Nothing can be taken while nothing runs.
    public func isAvailable(in state: TimerState) -> Bool {
        switch (self, state) {
        case (_, .idle), (.breakOrEndBreak, .paused), (.pauseOrResume, .idleBreak): false
        default: true
        }
    }

    /// Whether a break of a chosen length can start in `state`: while
    /// working, and while nothing runs. Not while paused, as before, and not
    /// on a break, where Break ends the break instead.
    public static func canStartBreak(in state: TimerState) -> Bool {
        state == .working || state == .idle
    }

    /// Starts a break of `minutes` at `now`.
    ///
    /// While working, the engine starts it inside the block. While nothing
    /// runs, `idleBreak` becomes a new break with no block, which nothing
    /// stores. Throws ``TimerEngineError/invalidMinutes`` when `minutes` is
    /// zero or less, or longer than ``IdleBreak/maximumLength`` with nothing
    /// running, and ``TimerEngineError/notAllowed(_:)`` in any other state.
    public static func startBreak(
        minutes: Int,
        with engine: TimerEngine,
        idleBreak: inout IdleBreak?,
        at now: Date,
    ) throws {
        guard minutes > 0 else { throw TimerEngineError.invalidMinutes }
        let status = try engine.settle(at: now)
        idleBreak = idleBreak?.running(beside: status, at: now)
        let state = idleBreak == nil ? status.state : .idleBreak
        guard canStartBreak(in: state) else { throw TimerEngineError.notAllowed(state) }
        if state == .working {
            try engine.startBreak(minutes: minutes, at: now)
            return
        }
        let end = now.addingTimeInterval(TimeInterval(minutes) * 60)
        guard let started = IdleBreak(start: now, end: end) else { throw TimerEngineError.invalidMinutes }
        idleBreak = started
    }

    /// Takes the action at `now`: on `idleBreak` while it runs, otherwise on
    /// the running block through `engine`, as ``perform(with:at:)``.
    ///
    /// On a break with no block, End break ends it, with nothing after it, and
    /// +15 moves its end later. Throws ``TimerEngineError/notAllowed(_:)``
    /// when the action is not available in the state at `now`, and
    /// ``TimerEngineError/invalidMinutes`` when +15 would make the break
    /// longer than ``IdleBreak/maximumLength``. A break that is over at `now`
    /// becomes `nil` first.
    public func perform(with engine: TimerEngine, idleBreak: inout IdleBreak?, at now: Date) throws {
        idleBreak = try idleBreak?.running(beside: engine.settle(at: now), at: now)
        guard idleBreak != nil else { return try perform(with: engine, at: now) }
        guard isAvailable(in: .idleBreak) else { throw TimerEngineError.notAllowed(.idleBreak) }
        switch self {
        case .breakOrEndBreak: idleBreak = nil
        case .extend:
            let added = TimeInterval(TimerEngine.defaultExtendMinutes) * 60
            guard let running = idleBreak,
                  let longer = IdleBreak(start: running.start, end: running.end.addingTimeInterval(added))
            else { throw TimerEngineError.invalidMinutes }
            idleBreak = longer
        case .pauseOrResume: break
        }
    }

    /// Takes the action on the running block at `now` through `engine`.
    ///
    /// Throws ``TimerEngineError/notAllowed(_:)`` when it is not available in
    /// the state at `now`.
    public func perform(with engine: TimerEngine, at now: Date) throws {
        let state = try engine.settle(at: now).state
        guard isAvailable(in: state) else { throw TimerEngineError.notAllowed(state) }
        switch (self, state) {
        case (.pauseOrResume, .paused): try engine.resume(at: now)
        case (.pauseOrResume, _): try engine.pause(at: now)
        case (.breakOrEndBreak, .onBreak): try engine.endBreak(at: now)
        case (.breakOrEndBreak, _): try engine.startBreak(at: now)
        case (.extend, _): try engine.extend(at: now)
        }
    }
}
