import Foundation
import SwiftData

/// The entries of one local day with their totals, as the window's Today and
/// History show them and as the panel's "Today: h:mm tracked" counts them.
///
/// A day runs from midnight to midnight in the calendar's time zone, and
/// never past `now`. An entry that crosses midnight is stored once and shows
/// on each day with its part of the time. A running entry counts up to `now`.
public struct DayLog {
    /// One entry's part of the day.
    public struct Item: Identifiable {
        /// The stored entry. Editing it edits the one entry, whichever day it is shown on.
        public let entry: TimeEntry
        /// Where the part shown starts: the entry's start, or midnight when it began on an earlier day.
        public let start: Date
        /// Where the part shown ends: the entry's end, the next midnight, or `now`.
        public let end: Date
        /// Whether the entry is still running.
        public let isRunning: Bool
        /// Whether the part counts toward the totals. See ``SchemaV1/TimeEntry/countsAsTracked``.
        public let counts: Bool

        /// The stored entry's identifier.
        public var id: PersistentIdentifier {
            entry.persistentModelID
        }

        /// The length of the part shown.
        public var length: TimeInterval {
            max(0, end.timeIntervalSince(start))
        }
    }

    /// One workspace's tracked time on the day.
    public struct Total: Identifiable {
        /// The workspace, archived or not.
        public let workspace: Workspace
        /// The counted time of its entries.
        public let tracked: TimeInterval

        /// The workspace's identifier.
        public var id: PersistentIdentifier {
            workspace.persistentModelID
        }
    }

    /// Midnight at the start of the day.
    public let day: Date
    /// The day's entries, earliest first.
    public let items: [Item]
    /// The tracked time per workspace that has an entry on the day: active
    /// ones in their order, then archived ones.
    public let totals: [Total]
    /// The day's tracked time over every workspace.
    public let total: TimeInterval

    /// The log of the day that contains `date`, read from `context` as it stands at `now`.
    public init(day date: Date, in context: ModelContext, now: Date, calendar: Calendar) throws {
        let dayStart = calendar.startOfDay(for: date)
        let nextDay = calendar.date(byAdding: .day, value: 1, to: dayStart) ?? dayStart.addingTimeInterval(86400)
        let until = min(nextDay, now)
        day = dayStart
        guard until > dayStart else {
            items = []
            totals = []
            total = 0
            return
        }
        let entries = try context.fetch(FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                if let end = entry.end {
                    entry.start < until && end > dayStart
                } else {
                    entry.start < until
                }
            },
            sortBy: [SortDescriptor(\.start)],
        ))
        items = entries.map { entry in
            Item(
                entry: entry,
                start: max(entry.start, dayStart),
                end: min(entry.end ?? now, until),
                isRunning: entry.end == nil,
                counts: entry.countsAsTracked,
            )
        }
        var byWorkspace: [PersistentIdentifier: (Workspace, TimeInterval)] = [:]
        for item in items {
            guard let workspace = item.entry.workspace else { continue }
            let tracked = item.counts ? item.length : 0
            byWorkspace[workspace.persistentModelID, default: (workspace, 0)].1 += tracked
        }
        totals = byWorkspace.values
            .map { Total(workspace: $0.0, tracked: $0.1) }
            .sorted {
                ($0.workspace.isArchived ? 1 : 0, $0.workspace.sortOrder, $0.workspace.name)
                    < ($1.workspace.isArchived ? 1 : 0, $1.workspace.sortOrder, $1.workspace.name)
            }
        total = items.reduce(0) { $0 + ($1.counts ? $1.length : 0) }
    }

    /// Midnight at the start of the day before `day`.
    public static func day(before day: Date, calendar: Calendar) -> Date {
        calendar.date(byAdding: .day, value: -1, to: calendar.startOfDay(for: day)) ?? day
    }

    /// Midnight at the start of the day after `day`, or `nil` when that day
    /// is not earlier than the day of `now`. History shows only earlier days.
    public static func earlierDay(after day: Date, now: Date, calendar: Calendar) -> Date? {
        let next = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: day)) ?? day
        return next < calendar.startOfDay(for: now) ? next : nil
    }
}

public extension TimeEntry {
    /// Whether the entry counts toward tracked time.
    ///
    /// Work and meetings always count. A break counts only when its
    /// workspace counts breaks (``SchemaV1/Workspace/breaksCount``).
    var countsAsTracked: Bool {
        !(kind == .break && workspace?.breaksCount == false)
    }
}
