@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// Gregorian in Europe/Prague with Monday first, as History reads a Mac set
/// that way. In 2026 its clocks go forward on 29 March and back on 25 October.
let prague: Calendar = {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = TimeZone(identifier: "Europe/Prague") ?? .gmt
    calendar.firstWeekday = 2
    return calendar
}()

/// ``prague`` with Sunday first.
let sundayFirst: Calendar = {
    var calendar = prague
    calendar.firstWeekday = 1
    return calendar
}()

/// The instant of `day` `month` 2026 at `hour`:`minute` on Prague's clock.
func local(_ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0, second: Int = 0, year: Int = 2026) -> Date {
    let parts = DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second)
    return prague.date(from: parts) ?? .distantPast
}

/// Friday 20 November 2026, 16:41:30 in Prague: the time History is read at
/// unless a test says otherwise.
let friday = local(11, 20, 16, 41, second: 30)

/// Inserts a finished entry and saves, naming `project` without the
/// assignment check, as an entry keeps a project that stopped being tracked.
@discardableResult
func insert(
    _ context: ModelContext, _ workspace: Workspace?, _ start: Date, _ end: Date?,
    kind: TimeEntryKind = .work, project: Project? = nil, note: String = "", source: TimeEntrySource = .timer,
) throws -> TimeEntry {
    let entry = TimeEntry(workspace: workspace, start: start, end: end, kind: kind, source: source, note: note)
    context.insert(entry)
    entry.project = project
    try context.save()
    return entry
}

/// Checks that `totals` equal the sum of the day views of its range: over
/// all, per bar, per workspace and per project, with breaks apart.
func expectMatchesDayViews(
    _ totals: RangeTotals, in context: ModelContext, now: Date, calendar: Calendar,
    sourceLocation: SourceLocation = #_sourceLocation,
) throws {
    let logs = try totals.range.days(calendar: calendar).map {
        try DayLog(day: $0, in: context, now: now, calendar: calendar)
    }
    #expect(totals.bars.flatMap(\.days).map(\.day) == logs.map(\.day), sourceLocation: sourceLocation)
    #expect(totals.total == tally(logs), sourceLocation: sourceLocation)
    #expect(byWorkspace(totals.totals) == byWorkspace(logs), sourceLocation: sourceLocation)
    #expect(byProject(totals.totals) == byProject(logs), sourceLocation: sourceLocation)
    for bar in totals.bars {
        let days = Set(bar.days.map(\.day))
        let barLogs = logs.filter { days.contains($0.day) }
        #expect(bar.total == tally(barLogs), sourceLocation: sourceLocation)
        #expect(byWorkspace(bar.totals) == byWorkspace(barLogs), sourceLocation: sourceLocation)
        #expect(byProject(bar.totals) == byProject(barLogs), sourceLocation: sourceLocation)
    }
    #expect(totals.bars.reduce(0) { $0 + $1.total.tracked } == totals.total.tracked, sourceLocation: sourceLocation)
}

/// The day views' tracked time, and the counted break rows in it, added up by hand.
func tally(_ logs: [DayLog]) -> Tally {
    let breaks = logs.flatMap(\.items).filter { $0.counts && $0.entry.kind == .break }
    return Tally(tracked: logs.reduce(0) { $0 + $1.total }, breaks: breaks.reduce(0) { $0 + $1.length })
}

/// The day views' tracked time per workspace name.
private func byWorkspace(_ logs: [DayLog]) -> [String: TimeInterval] {
    logs.flatMap(\.totals).reduce(into: [:]) { $0[$1.workspace.name, default: 0] += $1.tracked }
}

private func byWorkspace(_ totals: [RangeTotals.WorkspaceTotal]) -> [String: TimeInterval] {
    Dictionary(uniqueKeysWithValues: totals.map { ($0.workspace.name, $0.time.tracked) })
}

/// The day views' counted rows per `workspace/project`, added up by hand.
private func byProject(_ logs: [DayLog]) -> [String: TimeInterval] {
    logs.flatMap(\.items).reduce(into: [:]) { sums, item in
        guard let project = item.entry.project else { return }
        let key = "\(item.entry.workspace?.name ?? "")/\(project.name)"
        sums[key, default: 0] += item.counts ? item.length : 0
    }
}

private func byProject(_ totals: [RangeTotals.WorkspaceTotal]) -> [String: TimeInterval] {
    Dictionary(uniqueKeysWithValues: totals.flatMap { total in
        total.projects.map { ("\(total.workspace.name)/\($0.project.name)", $0.time.tracked) }
    })
}
