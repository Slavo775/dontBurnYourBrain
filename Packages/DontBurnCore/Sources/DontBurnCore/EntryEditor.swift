import Foundation
import SwiftData

/// Why a change to an entry was refused. Nothing was changed.
public enum EntryChangeError: Error, Equatable, Sendable {
    /// No workspace was chosen.
    case noWorkspace
    /// The end is not after the start.
    case endNotAfterStart
    /// The entry would end after now.
    case inFuture
    /// The entry would overlap another one, which runs from `start` to `end`.
    /// A running entry's `end` is the moment of the check.
    case overlaps(start: Date, end: Date)
    /// The entry belongs to the running block, so only its note may change
    /// and it may not be deleted until the block ends.
    case runningBlock
    /// The split time does not leave at least a whole minute on each side.
    case splitNotInside
}

/// The fields of an entry as the edit form holds them.
public struct EntryDraft {
    /// When the entry starts.
    public var start: Date
    /// When the entry ends.
    public var end: Date
    /// The entry's workspace.
    public var workspace: Workspace?
    /// What the time was spent on.
    public var kind: TimeEntryKind
    /// A free note.
    public var note: String

    /// A draft with the given fields.
    public init(start: Date, end: Date, workspace: Workspace?, kind: TimeEntryKind = .work, note: String = "") {
        self.start = start
        self.end = end
        self.workspace = workspace
        self.kind = kind
        self.note = note
    }

    /// A draft holding `entry` as stored. A running entry's end is `now`.
    public init(_ entry: TimeEntry, now: Date) {
        self.init(
            start: entry.start, end: entry.end ?? now, workspace: entry.workspace, kind: entry.kind, note: entry.note,
        )
    }
}

/// Corrects, adds, splits and deletes entries by hand, under the timer engine's rules
/// for intervals: the end is after the start, nothing lies in the future, and
/// no two entries overlap.
///
/// An entry of the running block takes a note only, and cannot be deleted,
/// because ``TimerEngine`` derives the block's end from the gaps between its
/// entries. Once the block has ended its entries are free to change. A manual
/// entry never belongs to a block. Every operation settles the timer at `now`
/// first, checks before it changes anything, and saves the context.
public struct EntryEditor {
    private let context: ModelContext

    /// An editor working on the entries in `context`.
    public init(context: ModelContext) {
        self.context = context
    }

    /// Whether only the note of `entry` may change: while it runs, or while
    /// its block runs. Call it after ``TimerEngine/settle(at:)``.
    public static func isNoteOnly(_ entry: TimeEntry) -> Bool {
        entry.end == nil || entry.block?.state == .running
    }

    /// The kinds the form offers: work and break, and the entry's own kind when it is another, such as a meeting.
    public static func kindChoices(keeping kind: TimeEntryKind?) -> [TimeEntryKind] {
        let offered: [TimeEntryKind] = [.work, .break]
        guard let kind, !offered.contains(kind) else { return offered }
        return offered + [kind]
    }

    /// The workspaces the form offers: the `active` ones, and `current` at the end when it is archived.
    public static func workspaceChoices(active: [Workspace], keeping current: Workspace?) -> [Workspace] {
        guard let current, !active.contains(where: { $0.id == current.id }) else { return active }
        return active + [current]
    }

    /// Adds a manual entry from `draft` and returns it.
    @discardableResult
    public func add(_ draft: EntryDraft, at now: Date) throws -> TimeEntry {
        try TimerEngine(context: context).settle(at: now)
        try check(draft, replacing: nil, at: now)
        let entry = TimeEntry(
            workspace: draft.workspace, start: draft.start, end: draft.end, kind: draft.kind, source: .manual,
            note: draft.note,
        )
        context.insert(entry)
        try context.save()
        return entry
    }

    /// Changes `entry` to `draft`. An entry of the running block takes only the note.
    public func update(_ entry: TimeEntry, to draft: EntryDraft, at now: Date) throws {
        try TimerEngine(context: context).settle(at: now)
        if Self.isNoteOnly(entry) {
            let unchanged = draft.start == entry.start && draft.kind == entry.kind
                && draft.workspace?.id == entry.workspace?.id && (entry.end == nil || draft.end == entry.end)
            guard unchanged else { throw EntryChangeError.runningBlock }
            entry.note = draft.note
            try context.save()
            return
        }
        try check(draft, replacing: entry, at: now)
        entry.start = draft.start
        entry.end = draft.end
        entry.kind = draft.kind
        entry.note = draft.note
        if entry.workspace?.id != draft.workspace?.id {
            entry.workspace = draft.workspace
            // A project names one workspace, so it cannot follow the entry to another.
            entry.project = nil
        }
        try context.save()
    }

    /// Deletes `entry`. Refused for an entry of the running block.
    public func delete(_ entry: TimeEntry, at now: Date) throws {
        try TimerEngine(context: context).settle(at: now)
        guard !Self.isNoteOnly(entry) else { throw EntryChangeError.runningBlock }
        context.delete(entry)
        try context.save()
    }

    /// Splits `entry` at `time`, rounded down to its minute, into two entries
    /// that together cover exactly the old one, and returns the second.
    ///
    /// Both keep the workspace, project, kind, note, source and block, so each
    /// can then be changed on its own. Refused for an entry that runs or whose
    /// block runs, for a time outside ``splitTimes(for:calendar:)``, and for
    /// anything ``check(_:replacing:at:)`` refuses in either half.
    @discardableResult
    public func split(_ entry: TimeEntry, at time: Date, now: Date, calendar: Calendar) throws -> TimeEntry {
        try TimerEngine(context: context).settle(at: now)
        guard !Self.isNoteOnly(entry), let end = entry.end else { throw EntryChangeError.runningBlock }
        let time = calendar.dateInterval(of: .minute, for: time)?.start ?? time
        guard Self.splitTimes(for: entry, calendar: calendar)?.contains(time) == true else {
            throw EntryChangeError.splitNotInside
        }
        let draft = EntryDraft(entry, now: now)
        var first = draft
        first.end = time
        var second = draft
        second.start = time
        try check(first, replacing: entry, at: now)
        try check(second, replacing: entry, at: now)
        let rest = TimeEntry(
            workspace: entry.workspace, start: time, end: end, kind: entry.kind, source: entry.source,
            block: entry.block, note: entry.note,
        )
        // Not through `assign(_:)`: a half keeps the project even when it is no longer tracked.
        rest.project = entry.project
        entry.end = time
        context.insert(rest)
        try context.save()
        return rest
    }

    /// The whole minutes `entry` can be split at, each leaving at least a
    /// minute on both sides, or `nil` when it runs or is too short.
    public static func splitTimes(for entry: TimeEntry, calendar: Calendar) -> ClosedRange<Date>? {
        guard let end = entry.end else { return nil }
        let earliest = entry.start.addingTimeInterval(60)
        let latest = end.addingTimeInterval(-60)
        let minute = calendar.dateInterval(of: .minute, for: earliest)
        let first = minute?.start == earliest ? earliest : minute?.end ?? earliest
        let last = calendar.dateInterval(of: .minute, for: latest)?.start ?? latest
        return first <= last ? first ... last : nil
    }

    /// Throws the first rule `draft` breaks, with `entry` itself left out of the overlap check.
    ///
    /// A running entry counts as running up to `now`. An entry of no length
    /// overlaps nothing.
    public func check(_ draft: EntryDraft, replacing entry: TimeEntry?, at now: Date) throws {
        guard draft.workspace != nil else { throw EntryChangeError.noWorkspace }
        guard draft.end > draft.start else { throw EntryChangeError.endNotAfterStart }
        guard draft.end <= now else { throw EntryChangeError.inFuture }
        if let other = try firstOverlap(from: draft.start, to: draft.end, excluding: entry, at: now) {
            throw EntryChangeError.overlaps(start: other.start, end: other.end)
        }
    }

    /// The latest stretch of `minutes` that ends on a whole minute, no later
    /// than `end` and `now`, and overlaps no entry, or `nil` when a hundred
    /// steps back find none. The default for a new entry.
    ///
    /// Each step that hits an entry moves the end back to that entry's
    /// start, so a running block pushes the stretch to before its first entry.
    public func latestFreeStretch(
        minutes: Int, endingBy end: Date, at now: Date, calendar: Calendar,
    ) throws -> DateInterval? {
        var end = min(end, now)
        for _ in 0 ..< 100 {
            end = calendar.dateInterval(of: .minute, for: end)?.start ?? end
            let start = end.addingTimeInterval(-TimeInterval(minutes) * 60)
            guard let other = try firstOverlap(from: start, to: end, excluding: nil, at: now) else {
                return DateInterval(start: start, end: end)
            }
            end = other.start
        }
        return nil
    }

    /// The earliest-starting entry other than `entry` that overlaps `start` to
    /// `end`, with a running one's end at `now`.
    private func firstOverlap(
        from start: Date, to end: Date, excluding entry: TimeEntry?, at now: Date,
    ) throws -> (start: Date, end: Date)? {
        let candidates = try context.fetch(FetchDescriptor<TimeEntry>(
            predicate: #Predicate { other in
                if let otherEnd = other.end {
                    other.start < end && otherEnd > start
                } else {
                    other.start < end
                }
            },
            sortBy: [SortDescriptor(\.start)],
        ))
        for other in candidates where other.persistentModelID != entry?.persistentModelID {
            let otherEnd = other.end ?? max(now, other.start)
            if other.start < otherEnd, other.start < end, otherEnd > start {
                return (other.start, otherEnd)
            }
        }
        return nil
    }
}
