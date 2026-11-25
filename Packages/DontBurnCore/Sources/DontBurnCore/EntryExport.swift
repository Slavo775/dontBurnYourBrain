import Foundation
import SwiftData

/// The entries of a range as CSV text, one row per entry, for a spreadsheet.
public enum EntryExport {
    /// The columns, in order.
    public static let columns = ["date", "start", "end", "minutes", "kind", "workspace", "project", "note", "source"]

    /// The entries that start in `interval` and before `now`, earliest first.
    ///
    /// An entry belongs to the range it starts in, so two neighbouring ranges
    /// never both hold it, even when it crosses midnight.
    public static func entries(
        startingIn interval: DateInterval, in context: ModelContext, now: Date,
    ) throws -> [TimeEntry] {
        let start = interval.start
        let end = min(interval.end, now)
        return try context.fetch(FetchDescriptor<TimeEntry>(
            predicate: #Predicate { $0.start >= start && $0.start < end },
            sortBy: [SortDescriptor(\.start)],
        ))
    }

    /// A header row and one row per entry, as RFC 4180 writes them: rows end
    /// with CRLF, and a field holding a comma, a quote or a line break is
    /// quoted, with its quotes doubled.
    ///
    /// The date is the start's day, and the times are ISO 8601 with the
    /// offset, both in `timeZone`. Minutes are the whole entry's whole
    /// minutes, rounded down. A running entry has an empty end and empty
    /// minutes. Kind and source are their stored values.
    public static func csv(_ entries: [TimeEntry], timeZone: TimeZone) -> String {
        let day = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()
        let time = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: timeZone)
        let rows = entries.map { entry in
            [
                entry.start.formatted(day),
                entry.start.formatted(time),
                entry.end?.formatted(time) ?? "",
                entry.end.map { String(Int(max(0, $0.timeIntervalSince(entry.start)) / 60)) } ?? "",
                entry.kindRaw,
                entry.workspace?.name ?? "",
                entry.project?.name ?? "",
                entry.note,
                entry.sourceRaw,
            ]
        }
        return ([columns] + rows)
            .map { $0.map(field).joined(separator: ",") + "\r\n" }
            .joined()
    }

    /// `value` quoted when it holds a comma, a quote or a line break.
    private static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
