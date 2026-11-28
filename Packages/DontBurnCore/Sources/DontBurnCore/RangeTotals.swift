import Foundation
import SwiftData

/// Tracked time, and the part of it spent in breaks.
///
/// What counts follows ``SchemaV2/TimeEntry/countsAsTracked``: work and
/// meetings always, a break only when its workspace counts breaks. A break
/// that does not count is in neither number.
public struct Tally: Equatable, Sendable {
    /// The counted time, as the day view's totals count it.
    public internal(set) var tracked: TimeInterval = 0
    /// The part of ``tracked`` spent in breaks.
    public internal(set) var breaks: TimeInterval = 0

    /// The part of ``tracked`` spent in work and meetings.
    public var work: TimeInterval {
        tracked - breaks
    }

    /// Adds `item`'s ``DayLog/Item/length`` when it counts.
    mutating func add(_ item: DayLog.Item) {
        guard item.counts else { return }
        tracked += item.length
        if item.entry.kind == .break {
            breaks += item.length
        }
    }
}

/// The totals of a week or a month, built from one ``DayLog`` per day, so they
/// always equal the sum of the day views.
///
/// Each day's entries are clipped to that day and to `now` as the day view
/// clips them, and their whole minutes are added up.
public struct RangeTotals {
    /// One project's time.
    public struct ProjectTotal: Identifiable {
        /// The project, archived or not.
        public let project: Project
        /// Its counted time.
        public let time: Tally

        /// The project's identifier.
        public var id: PersistentIdentifier {
            project.persistentModelID
        }
    }

    /// One workspace's time, with its projects.
    public struct WorkspaceTotal: Identifiable {
        /// The workspace, archived or not.
        public let workspace: Workspace
        /// Its counted time, entries without a project included.
        public let time: Tally
        /// Its projects with an entry in the range, in their order. Entries
        /// without a project are in ``time`` alone.
        public let projects: [ProjectTotal]

        /// The workspace's identifier.
        public var id: PersistentIdentifier {
            workspace.persistentModelID
        }
    }

    /// One bar of the chart: a day of a week, or the days of one week inside a month.
    public struct Bar: Identifiable {
        /// The bar's days, earliest first.
        public let days: [DayLog]
        /// The time per workspace with an entry on these days.
        public let totals: [WorkspaceTotal]
        /// The time of these days over every workspace.
        public let total: Tally

        /// Midnight at the start of the first day.
        public var start: Date {
            days.first?.day ?? .distantPast
        }

        /// The first day, which tells the bars apart.
        public var id: Date {
            start
        }
    }

    /// The week or the month.
    public let range: HistoryRange
    /// The bars, earliest first, together holding every day of the range once.
    public let bars: [Bar]
    /// The time per workspace with an entry in the range: active ones in
    /// their order, then archived ones.
    public let totals: [WorkspaceTotal]
    /// The range's time over every workspace: the sum of the day views' totals.
    public let total: Tally

    /// Whether no day of the range has an entry.
    public var isEmpty: Bool {
        bars.allSatisfy { $0.days.allSatisfy(\.items.isEmpty) }
    }

    /// The totals of `range`, read from `context` as it stands at `now`.
    public init(_ range: HistoryRange, in context: ModelContext, now: Date, calendar: Calendar) throws {
        self.range = range
        bars = try range.bars(calendar: calendar).map { days in
            let logs = try days.map { try DayLog(day: $0, in: context, now: now, calendar: calendar) }
            let (totals, total) = Self.tally(logs)
            return Bar(days: logs, totals: totals, total: total)
        }
        (totals, total) = Self.tally(bars.flatMap(\.days))
    }

    /// The time per workspace and project, and over all, of every item in `logs`.
    private static func tally(_ logs: [DayLog]) -> ([WorkspaceTotal], Tally) {
        var total = Tally()
        var workspaces: [PersistentIdentifier: (workspace: Workspace, time: Tally)] = [:]
        var projects: [PersistentIdentifier: [PersistentIdentifier: (project: Project, time: Tally)]] = [:]
        for item in logs.flatMap(\.items) {
            total.add(item)
            guard let workspace = item.entry.workspace else { continue }
            let key = workspace.persistentModelID
            workspaces[key, default: (workspace, Tally())].time.add(item)
            if let project = item.entry.project {
                projects[key, default: [:]][project.persistentModelID, default: (project, Tally())].time.add(item)
            }
        }
        let totals = workspaces.values
            .sorted {
                ($0.workspace.isArchived ? 1 : 0, $0.workspace.sortOrder, $0.workspace.name)
                    < ($1.workspace.isArchived ? 1 : 0, $1.workspace.sortOrder, $1.workspace.name)
            }
            .map { workspace, time in
                WorkspaceTotal(
                    workspace: workspace,
                    time: time,
                    projects: (projects[workspace.persistentModelID] ?? [:]).values
                        .sorted {
                            ($0.project.isArchived ? 1 : 0, $0.project.sortOrder, $0.project.name)
                                < ($1.project.isArchived ? 1 : 0, $1.project.sortOrder, $1.project.name)
                        }
                        .map { ProjectTotal(project: $0.project, time: $0.time) },
                )
            }
        return (totals, total)
    }
}
