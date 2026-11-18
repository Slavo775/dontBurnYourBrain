import Foundation
import SwiftData

/// What the timer is doing at a moment.
public enum TimerState: String, CaseIterable, Sendable {
    /// No block is running.
    case idle
    /// A block is running with a work or meeting entry.
    case working
    /// A block is open without a running entry, and its end moves later.
    case paused
    /// A block is running with a break entry.
    case onBreak
}

/// The timer's report for one moment.
public struct TimerStatus: Equatable, Sendable {
    /// What the timer is doing.
    public let state: TimerState
    /// When the running block ends, or `nil` when nothing runs. While paused
    /// it moves later with the moment asked about.
    public let plannedEnd: Date?
    /// The time left in the running block, never below zero, or `nil` when nothing runs.
    public let blockTimeLeft: TimeInterval?
    /// The time left in the running break, never below zero, or `nil` when
    /// not on a break or the break has no planned length.
    public let breakTimeLeft: TimeInterval?

    /// The report when nothing runs.
    public static let idle = TimerStatus(state: .idle, plannedEnd: nil, blockTimeLeft: nil, breakTimeLeft: nil)
}

/// Why the timer engine refused an operation. Nothing was changed except settling.
public enum TimerEngineError: Error, Equatable, Sendable {
    /// The operation makes no sense in this state, such as Pause while paused.
    case notAllowed(TimerState)
    /// A length or an extension of zero minutes or less.
    case invalidMinutes
}

/// Decides what happens to blocks and entries when the user starts, pauses,
/// resumes, takes a break, extends, switches and ends.
///
/// The engine keeps no state of its own. The running block is the one stored
/// with state `.running`, and the running entry is the one without an end, so
/// the engine gives the same answers after a restart. Nothing is scheduled:
/// the app calls ``settle(at:)`` on a timer and at start-up, and every
/// operation settles first at the time it is given.
///
/// A block's planned end is derived, never stored: its planned start plus its
/// planned minutes plus every gap between its entries. While paused, the open
/// gap up to the moment asked about counts too, so the time left stands still.
///
/// Every operation saves the context. An operation in a state where it makes
/// no sense throws ``TimerEngineError/notAllowed(_:)`` after settling. A time
/// earlier than the stored ones (a clock moved back) is raised to the latest
/// stored time, so no entry ends before it starts and no two overlap.
public struct TimerEngine {
    /// A break's length when none is given, in minutes.
    public static let defaultBreakMinutes = 5
    /// How much Extend adds when no amount is given, in minutes.
    public static let defaultExtendMinutes = 15

    private let context: ModelContext

    /// An engine working on the blocks and entries in `context`.
    public init(context: ModelContext) {
        self.context = context
    }

    /// Applies everything that became due by `now` and reports the state at `now`.
    ///
    /// A break whose time is up ends at its planned end and a work entry starts
    /// there. A block past its planned end closes at the planned end, with its
    /// running entry, even when `now` is much later: time asleep or quit counts
    /// as worked up to the planned end. A break is clipped at the block's end.
    /// A paused block never times out.
    @discardableResult
    public func settle(at now: Date) throws -> TimerStatus {
        for block in try runningBlocks() {
            settle(block, at: now)
        }
        if context.hasChanges {
            try context.save()
        }
        guard let block = try runningBlocks().last else { return .idle }
        return status(of: block, at: now)
    }

    /// Starts a block for `workspace` with a running work entry.
    ///
    /// Whatever runs ends first, at the same instant. The length is
    /// `minutes`, or the workspace's default length when `nil`. Throws
    /// ``TimerEngineError/invalidMinutes`` or a ``ProjectAssignmentError``
    /// before changing anything.
    public func start(_ workspace: Workspace, minutes: Int? = nil, project: Project? = nil, at now: Date) throws {
        let minutes = minutes ?? workspace.defaultBlockMinutes
        guard minutes > 0 else { throw TimerEngineError.invalidMinutes }
        try project?.checkAssignable(to: workspace)
        try settle(at: now)

        var start = now
        for entry in try openEntries() {
            start = max(start, close(entry, at: now))
        }
        for block in try runningBlocks() {
            start = max(start, latestEnd(of: block) ?? start)
            block.state = .done
        }
        let block = TimeBlock(workspace: workspace, plannedStart: start, plannedMinutes: minutes, state: .running)
        context.insert(block)
        block.project = project
        begin(.work, in: block, at: start)
        try context.save()
    }

    /// Ends the running block and starts one for `workspace` at its default length.
    ///
    /// Allowed only while a block runs, paused or not.
    public func switchTo(_ workspace: Workspace, project: Project? = nil, at now: Date) throws {
        _ = try current(at: now, allowed: [.working, .paused, .onBreak])
        try start(workspace, project: project, at: now)
    }

    /// Ends the running entry. The block stays open and its end moves later
    /// until ``resume(at:)``. Allowed while working or on a break.
    public func pause(at now: Date) throws {
        let (block, _) = try current(at: now, allowed: [.working, .onBreak])
        if let open = openEntry(of: block) {
            close(open, at: now)
        }
        try context.save()
    }

    /// Starts a new work entry in the paused block. Allowed only while paused.
    public func resume(at now: Date) throws {
        let (block, _) = try current(at: now, allowed: [.paused])
        begin(.work, in: block, at: max(now, latestEnd(of: block) ?? now))
        try context.save()
    }

    /// Ends the work entry and starts a break of `minutes` inside the block.
    /// The block's end does not move. Allowed only while working.
    public func startBreak(minutes: Int = defaultBreakMinutes, at now: Date) throws {
        guard minutes > 0 else { throw TimerEngineError.invalidMinutes }
        let (block, _) = try current(at: now, allowed: [.working])
        guard let open = openEntry(of: block) else { return }
        begin(.break, in: block, at: close(open, at: now)).plannedMinutes = minutes
        try context.save()
    }

    /// Ends the break and starts a new work entry. Allowed only on a break.
    public func endBreak(at now: Date) throws {
        let (block, _) = try current(at: now, allowed: [.onBreak])
        guard let open = openEntry(of: block) else { return }
        begin(.work, in: block, at: close(open, at: now))
        try context.save()
    }

    /// Adds `minutes` to the running block's planned length. Allowed while a block runs, paused or not.
    public func extend(by minutes: Int = defaultExtendMinutes, at now: Date) throws {
        guard minutes > 0 else { throw TimerEngineError.invalidMinutes }
        let (block, _) = try current(at: now, allowed: [.working, .paused, .onBreak])
        block.plannedMinutes += minutes
        try context.save()
    }

    /// Ends the running entry and the block now. Allowed while a block runs, paused or not.
    public func end(at now: Date) throws {
        let (block, _) = try current(at: now, allowed: [.working, .paused, .onBreak])
        if let open = openEntry(of: block) {
            close(open, at: now)
        }
        block.state = .done
        try context.save()
    }

    // MARK: - Reading the store

    /// Settles, then returns the current block when its state is in `allowed`.
    private func current(at now: Date, allowed: Set<TimerState>) throws -> (TimeBlock, TimerState) {
        let status = try settle(at: now)
        guard allowed.contains(status.state), let block = try runningBlocks().last else {
            throw TimerEngineError.notAllowed(status.state)
        }
        return (block, status.state)
    }

    /// Running blocks, oldest first. More than one only in a damaged store;
    /// the newest counts as current and Start ends them all.
    private func runningBlocks() throws -> [TimeBlock] {
        let running = TimeBlockState.running.rawValue
        return try context.fetch(FetchDescriptor<TimeBlock>(
            predicate: #Predicate { $0.stateRaw == running },
            sortBy: [SortDescriptor(\.plannedStart)],
        ))
    }

    private func openEntries() throws -> [TimeEntry] {
        try context.fetch(FetchDescriptor<TimeEntry>(predicate: #Predicate { $0.end == nil }))
    }

    private func openEntry(of block: TimeBlock) -> TimeEntry? {
        block.entries?.first { $0.end == nil }
    }

    private func latestEnd(of block: TimeBlock) -> Date? {
        block.entries?.compactMap(\.end).max()
    }

    // MARK: - Derived times

    /// The block's planned start and length plus every gap between its
    /// entries, and while paused the open gap up to `now`.
    private func plannedEnd(of block: TimeBlock, at now: Date) -> Date {
        let planned = block.plannedStart.addingTimeInterval(TimeInterval(block.plannedMinutes) * 60)
        var paused: TimeInterval = 0
        var lastEnd = block.plannedStart
        for entry in (block.entries ?? []).sorted(by: { $0.start < $1.start }) {
            paused += max(0, entry.start.timeIntervalSince(lastEnd))
            guard let end = entry.end else { return planned.addingTimeInterval(paused) }
            lastEnd = max(lastEnd, end)
        }
        return planned.addingTimeInterval(paused + max(0, now.timeIntervalSince(lastEnd)))
    }

    private func breakEnd(of entry: TimeEntry) -> Date? {
        guard entry.kind == .break, let minutes = entry.plannedMinutes else { return nil }
        return entry.start.addingTimeInterval(TimeInterval(minutes) * 60)
    }

    private func status(of block: TimeBlock, at now: Date) -> TimerStatus {
        let end = plannedEnd(of: block, at: now)
        let open = openEntry(of: block)
        let state: TimerState = switch open?.kind {
        case nil: .paused
        case .break: .onBreak
        default: .working
        }
        let breakLeft = open.flatMap(breakEnd(of:)).map { max(0, min($0, end).timeIntervalSince(now)) }
        return TimerStatus(
            state: state,
            plannedEnd: end,
            blockTimeLeft: max(0, end.timeIntervalSince(now)),
            breakTimeLeft: breakLeft,
        )
    }

    // MARK: - Changing the store

    private func settle(_ block: TimeBlock, at now: Date) {
        while let open = openEntry(of: block) {
            let blockEnd = plannedEnd(of: block, at: now)
            if let breakEnd = breakEnd(of: open), breakEnd < blockEnd, breakEnd <= now {
                begin(.work, in: block, at: close(open, at: breakEnd))
                continue
            }
            if blockEnd <= now {
                close(open, at: blockEnd)
                block.state = .done
            }
            return
        }
    }

    /// Ends `entry` at `time`, or at its start when `time` is earlier, and returns the end.
    @discardableResult
    private func close(_ entry: TimeEntry, at time: Date) -> Date {
        let end = max(time, entry.start)
        entry.end = end
        return end
    }

    /// A running entry in `block`, with the block's workspace and project.
    @discardableResult
    private func begin(_ kind: TimeEntryKind, in block: TimeBlock, at start: Date) -> TimeEntry {
        let entry = TimeEntry(workspace: block.workspace, start: start, end: nil, kind: kind, block: block)
        context.insert(entry)
        entry.project = block.project
        return entry
    }
}
