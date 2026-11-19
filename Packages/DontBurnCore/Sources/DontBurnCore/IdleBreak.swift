import Foundation

/// A break taken while no block runs.
///
/// Time between blocks belongs to nothing, so this break is never stored as an
/// entry, names no workspace and counts toward no total. It only counts down,
/// and its end is announced like the end of a break in a block. The app keeps
/// it in its defaults, so it survives a restart. Starting a block ends it.
///
/// Once it stops running it is kept as finished, with the end it really had,
/// since untracked time starts after it. See
/// ``MenuBarLabel/untrackedStart(in:appStart:now:calendar:idleBreak:)``.
public struct IdleBreak: Equatable, Sendable {
    /// The longest a break may run from its start, and the farthest its end
    /// may lie ahead. One read back that runs longer, ends before it starts,
    /// or ends farther ahead is taken as damaged.
    public static let maximumLength: TimeInterval = 24 * 60 * 60

    /// When it started.
    public let start: Date
    /// When it ends.
    public private(set) var end: Date

    /// A break from `start` to `end`, or `nil` when it ends before it starts
    /// or runs longer than ``maximumLength``.
    public init?(start: Date, end: Date) {
        guard start <= end, end.timeIntervalSince(start) <= Self.maximumLength else { return nil }
        self.start = start
        self.end = end
    }

    /// The time left at `now`, never below zero.
    public func timeLeft(at now: Date) -> TimeInterval {
        max(0, end.timeIntervalSince(now))
    }

    /// Whether it is over at `now`.
    public func isOver(at now: Date) -> Bool {
        end <= now
    }

    /// How much of it is used up at `now`, from 0 to 1.
    public func progress(at now: Date) -> Double {
        let length = end.timeIntervalSince(start)
        guard length > 0 else { return 1 }
        return min(1, max(0, now.timeIntervalSince(start) / length))
    }

    /// Moves its end `minutes` later, with no ceiling. +15 through
    /// ``QuickAction/perform(with:idleBreak:at:)`` refuses to pass ``maximumLength``.
    public mutating func extend(by minutes: Int) {
        end = end.addingTimeInterval(TimeInterval(minutes) * 60)
    }

    /// The timer's report for this break at `now`: ``TimerState/idleBreak``
    /// with the break's time left and no block.
    public func status(at now: Date) -> TimerStatus {
        TimerStatus(state: .idleBreak, plannedEnd: nil, blockTimeLeft: nil, breakTimeLeft: timeLeft(at: now))
    }

    /// This break while it still runs beside a timer that reports `status` at
    /// `now`, otherwise `nil`: it is over, a block runs, which always wins, or
    /// it is damaged at `now` (see ``ended(at:)``).
    public func running(beside status: TimerStatus, at now: Date) -> Self? {
        guard status.state == .idle, !isOver(at: now), isSound(at: now) else { return nil }
        return self
    }

    /// This break once it stopped running at `now`: ended at `now` when it
    /// would have run later, such as when ended by hand or by a block, or as
    /// it is when it ran out. `nil` when it is damaged at `now`: it starts
    /// after `now`, or ends more than ``maximumLength`` after it.
    ///
    /// ponytail: a finished break is told from a running one only by its end.
    /// After the clock moves back past its start it is dropped, and between
    /// its start and its end it runs again until the end.
    public func ended(at now: Date) -> Self? {
        guard isSound(at: now) else { return nil }
        var ended = self
        ended.end = min(end, now)
        return ended
    }

    /// Whether it started by `now` and ends at most ``maximumLength`` after it.
    /// Anything else only a damaged value or a clock moved back gives.
    private func isSound(at now: Date) -> Bool {
        start <= now && end.timeIntervalSince(now) <= Self.maximumLength
    }
}
