import Foundation
import SwiftData

/// What the compact panel shows while a block runs, at one moment.
///
/// The times are already formatted as digits. The app adds the words.
public struct CompactPanel: Equatable, Sendable {
    /// The line under the countdown.
    public enum Line: Equatable, Sendable {
        /// Working: the block's planned length, such as `2:00` in "left of 2:00".
        case leftOf(String)
        /// The block is paused.
        case paused
        /// A break is running, and work continues in the named workspace after it.
        case onBreak(returnTo: String)
    }

    /// The running block's workspace name, in full.
    public let name: String
    /// The running block's workspace color.
    public let color: WorkspaceColor
    /// What the timer is doing: working, paused or on a break.
    public let state: TimerState
    /// The large part of the countdown: hours and minutes, such as `1:24`,
    /// or minutes alone, such as `24`, under an hour. On a break it counts the
    /// break, otherwise the block.
    public let clock: String
    /// The small part of the countdown, the seconds, such as `:10`.
    public let seconds: String
    /// The line under the countdown.
    public let line: Line
    /// How much of the block's planned length is used up, from 0 to 1.
    public let progress: Double
    /// Today's tracked time in hours and minutes, such as `0:10`.
    public let trackedToday: String

    /// What the panel shows for `status`, or `nil` when nothing runs.
    ///
    /// `block` is the running block, see ``TimerEngine/runningBlock()``.
    /// `tracked` is today's tracked time, see
    /// ``trackedToday(in:now:calendar:)``. Every time is rounded down to the
    /// whole second, as in the menu bar.
    public init?(status: TimerStatus, block: TimeBlock?, tracked: TimeInterval) {
        guard status.state != .idle, let block, let blockLeft = status.blockTimeLeft else { return nil }
        let workspace = block.workspace
        name = workspace?.name ?? ""
        color = workspace?.color ?? .teal
        state = status.state
        let shown = status.state == .onBreak ? status.breakTimeLeft ?? blockLeft : blockLeft
        (clock, seconds) = Self.split(shown)
        let planned = TimeInterval(max(0, block.plannedMinutes)) * 60
        line = switch status.state {
        case .paused: .paused
        case .onBreak: .onBreak(returnTo: name)
        default: .leftOf(MenuBarLabel.hoursAndMinutes(planned))
        }
        progress = planned > 0 ? min(1, max(0, 1 - blockLeft / planned)) : 1
        trackedToday = MenuBarLabel.hoursAndMinutes(tracked)
    }

    /// When the panel's seconds change next after `now`, or `nil` while
    /// nothing counts down: nothing runs, or the block is paused.
    public static func nextRedraw(status: TimerStatus, after now: Date) -> Date? {
        let left: TimeInterval? = switch status.state {
        case .idle, .paused: nil
        case .onBreak: status.breakTimeLeft ?? status.blockTimeLeft
        case .working: status.blockTimeLeft
        }
        return left.map { MenuBarLabel.nextCountDown(left: $0, step: 1, after: now) }
    }

    /// Today's tracked time up to `now`: every entry's part between the start
    /// of today and `now`, running ones included.
    ///
    /// Work and meetings always count. A break counts only when its
    /// workspace counts breaks (``SchemaV1/Workspace/breaksCount``).
    public static func trackedToday(in context: ModelContext, now: Date, calendar: Calendar) throws -> TimeInterval {
        let startOfToday = calendar.startOfDay(for: now)
        // Only entries that reach into today, since this runs every second while the panel is open.
        let entries = try context.fetch(FetchDescriptor<TimeEntry>(predicate: #Predicate { entry in
            if let end = entry.end {
                entry.start < now && end > startOfToday
            } else {
                entry.start < now
            }
        }))
        return entries.reduce(0) { total, entry in
            if entry.kind == .break, entry.workspace?.breaksCount == false {
                return total
            }
            let start = max(entry.start, startOfToday)
            let end = min(entry.end ?? now, now)
            return total + max(0, end.timeIntervalSince(start))
        }
    }

    /// `h:mm` and `:ss` from one hour on, `m` and `:ss` below it, rounded down.
    static func split(_ seconds: TimeInterval) -> (String, String) {
        let whole = max(0, Int(seconds))
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
    /// Pause while working or on a break, Resume while paused.
    case pauseOrResume
    /// Take a break while working, End break on a break.
    case breakOrEndBreak
    /// Add ``TimerEngine/defaultExtendMinutes`` to the block.
    case extend

    /// Whether the action can be taken in `state`.
    ///
    /// A break cannot start while paused, because the engine starts a break
    /// only from work. Nothing can be taken while nothing runs.
    public func isAvailable(in state: TimerState) -> Bool {
        switch (self, state) {
        case (_, .idle), (.breakOrEndBreak, .paused): false
        default: true
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
