import Foundation

/// A break taken while no block runs.
///
/// Time between blocks belongs to nothing, so this break is never stored as an
/// entry, names no workspace and counts toward no total. It only counts down,
/// and its end is announced like the end of a break in a block. The app keeps
/// it in its defaults, so it survives a restart. Starting a block ends it.
public struct IdleBreak: Equatable, Sendable {
    /// The longest a break may run from its start. One read back that runs
    /// longer, or ends before it starts, is taken as damaged.
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

    /// Moves its end `minutes` later.
    public mutating func extend(by minutes: Int) {
        end = end.addingTimeInterval(TimeInterval(minutes) * 60)
    }

    /// The timer's report for this break at `now`: ``TimerState/idleBreak``
    /// with the break's time left and no block.
    public func status(at now: Date) -> TimerStatus {
        TimerStatus(state: .idleBreak, plannedEnd: nil, blockTimeLeft: nil, breakTimeLeft: timeLeft(at: now))
    }

    /// This break while it still runs beside a timer that reports `status` at
    /// `now`, otherwise `nil`: it is over, or a block runs, which always wins.
    public func running(beside status: TimerStatus, at now: Date) -> Self? {
        status.state == .idle && !isOver(at: now) ? self : nil
    }
}
