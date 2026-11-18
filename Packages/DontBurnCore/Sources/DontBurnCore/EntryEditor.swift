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

/// Corrects, adds and deletes entries by hand, under the timer engine's rules
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

    /// Throws the first rule `draft` breaks, with `entry` itself left out of the overlap check.
    ///
    /// A running entry counts as running up to `now`. An entry of no length
    /// overlaps nothing.
    public func check(_ draft: EntryDraft, replacing entry: TimeEntry?, at now: Date) throws {
        guard draft.workspace != nil else { throw EntryChangeError.noWorkspace }
        guard draft.end > draft.start else { throw EntryChangeError.endNotAfterStart }
        guard draft.end <= now else { throw EntryChangeError.inFuture }
        let start = draft.start, end = draft.end
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
                throw EntryChangeError.overlaps(start: other.start, end: otherEnd)
            }
        }
    }
}
