import Foundation
import SwiftData

/// What the menu bar item shows at one moment.
///
/// The times are already formatted as digits, such as `1:24` or `4:59`. The
/// app adds the dot or the cup and the words.
public enum MenuBarLabel: Equatable, Sendable {
    /// A block is running: the workspace's dot and name and the time left,
    /// in hours and minutes, or in minutes and seconds in the last five minutes.
    case running(name: String, color: WorkspaceColor, time: String)
    /// A block is paused: the workspace's dot and name.
    case paused(name: String, color: WorkspaceColor)
    /// A break is running: the cup and the break time left in minutes and
    /// seconds, or `nil` when the break has no planned length.
    case onBreak(time: String?)
    /// Nothing runs: the outline dot, and after 15 minutes the untracked time
    /// in hours and minutes.
    case idle(untracked: String?)

    /// Below this much time left, a running block shows minutes and seconds.
    public static let secondsThreshold: TimeInterval = 5 * 60
    /// From this much time without a running entry on, the untracked time shows.
    public static let untrackedThreshold: TimeInterval = 15 * 60
    /// The longest workspace name shown, in characters, including the ellipsis.
    public static let maximumNameLength = 16
    /// The longest wait between two redraws, so a change in the store shows within it.
    static let maximumRedrawInterval: TimeInterval = 60
    /// How long after the instant the digits change the redraw is due, so a
    /// timer that fires exactly on time already sees the new digits.
    static let redrawDelay: TimeInterval = 0.001

    /// What the item shows for `status` at `now`.
    ///
    /// `workspace` is the running block's workspace, ignored when nothing
    /// runs. `untrackedSince` is where the untracked time starts, see
    /// ``untrackedStart(in:appStart:now:calendar:)``.
    ///
    /// Every time is rounded down to the whole minute or second, as in the
    /// panel: a two-hour block shows `2:00` only at its first instant, then
    /// `1:59`, and 5:00 left still shows `0:05`. A block or a break shows
    /// `0:00` in its last second, until the next redraw settles it.
    public init(status: TimerStatus, workspace: Workspace?, untrackedSince: Date, at now: Date) {
        let name = Self.shortened(workspace?.name ?? "")
        let color = workspace?.color ?? .teal
        switch status.state {
        case .idle:
            let untracked = now.timeIntervalSince(untrackedSince)
            self = .idle(untracked: untracked >= Self.untrackedThreshold ? Self.hoursAndMinutes(untracked) : nil)
        case .paused:
            self = .paused(name: name, color: color)
        case .onBreak:
            self = .onBreak(time: status.breakTimeLeft.map(Self.minutesAndSeconds))
        case .working:
            let left = status.blockTimeLeft ?? 0
            let time = left < Self.secondsThreshold ? Self.minutesAndSeconds(left) : Self.hoursAndMinutes(left)
            self = .running(name: name, color: color, time: time)
        }
    }

    /// When what the item shows changes next after `now`, at the latest a minute after it.
    ///
    /// The instants line up with the block's or the break's end, so each
    /// redraw lands just after the digits change: every minute while a block
    /// has five minutes or more left, every second below five minutes and
    /// during a break, and every minute of untracked time. When the block or
    /// the break reaches its end, the redraw is due at once, so the next
    /// settle closes it.
    public static func nextRedraw(status: TimerStatus, untrackedSince: Date, after now: Date) -> Date {
        let latest = now.addingTimeInterval(maximumRedrawInterval)
        let next: Date? = switch status.state {
        case .idle:
            nextCountUp(from: untrackedSince, after: now)
        case .paused:
            nil
        case .onBreak:
            status.breakTimeLeft.map { nextCountDown(left: $0, step: 1, after: now) }
        case .working:
            status.blockTimeLeft.map { left in
                nextCountDown(left: left, step: left < secondsThreshold ? 1 : 60, after: now)
            }
        }
        return min(next ?? latest, latest)
    }

    /// Where the untracked time starts: the end of the latest entry that
    /// ended today by `now`, or else the app's start, but never before today.
    ///
    /// Entries of every kind and source count. One that ends after `now`,
    /// such as a meeting later today, does not.
    public static func untrackedStart(
        in context: ModelContext,
        appStart: Date,
        now: Date,
        calendar: Calendar,
    ) throws -> Date {
        var descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                if let end = entry.end {
                    end <= now
                } else {
                    false
                }
            },
            sortBy: [SortDescriptor(\.end, order: .reverse)],
        )
        descriptor.fetchLimit = 1
        let startOfToday = calendar.startOfDay(for: now)
        if let lastEnd = try context.fetch(descriptor).first?.end, lastEnd >= startOfToday {
            return lastEnd
        }
        return max(appStart, startOfToday)
    }

    /// `name` on one line, cut to ``maximumNameLength`` characters with an
    /// ellipsis when it is longer.
    static func shortened(_ name: String) -> String {
        let line = name.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard line.count > maximumNameLength else { return line }
        return line.prefix(maximumNameLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    /// `h:mm` for whole minutes in `seconds`, rounded down, such as `0:10`.
    public static func hoursAndMinutes(_ seconds: TimeInterval) -> String {
        let minutes = max(0, Int(seconds / 60))
        return "\(minutes / 60):" + twoDigits(minutes % 60)
    }

    /// `m:ss` for whole seconds in `seconds`, rounded down.
    static func minutesAndSeconds(_ seconds: TimeInterval) -> String {
        let whole = max(0, Int(seconds))
        return "\(whole / 60):" + twoDigits(whole % 60)
    }

    private static func twoDigits(_ value: Int) -> String {
        value < 10 ? "0\(value)" : "\(value)"
    }

    /// Just after the instant when a countdown with `left` shown in whole
    /// steps of `step` seconds, rounded down, shows one step less. With
    /// nothing left, at once, so the end is settled.
    static func nextCountDown(left: TimeInterval, step: TimeInterval, after now: Date) -> Date {
        let shownSteps = max(0, (left / step).rounded(.down))
        return now.addingTimeInterval(max(0, left - shownSteps * step) + redrawDelay)
    }

    /// The next whole minute counted from `start`, or the untracked threshold
    /// when it lies ahead.
    private static func nextCountUp(from start: Date, after now: Date) -> Date {
        let elapsed = now.timeIntervalSince(start)
        guard elapsed >= untrackedThreshold else { return start.addingTimeInterval(untrackedThreshold) }
        return start.addingTimeInterval(((elapsed / 60).rounded(.down) + 1) * 60)
    }
}
