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

    /// A UTF-8 byte-order mark, then a header row and one row per entry, as
    /// RFC 4180 writes them: rows end with CRLF, and a field holding a comma,
    /// a quote or a line break is quoted, with its quotes doubled.
    ///
    /// The mark is part of the text, so Excel on the Mac reads accented
    /// letters, and the caller writes the text as UTF-8 as it is.
    ///
    /// The date is the start's day, and the times are ISO 8601 with the
    /// offset, both in `timeZone`. Minutes are the whole entry's whole
    /// minutes, rounded down. A running entry has an empty end and empty
    /// minutes. Kind and source are their stored values.
    ///
    /// A text field (kind, workspace, project, note and source) that starts
    /// with `=`, `+`, `-`, `@`, a tab or a carriage return gets a leading `'`
    /// before it is quoted, so a spreadsheet shows it as text, not a formula.
    public static func csv(_ entries: [TimeEntry], timeZone: TimeZone) -> String {
        let day = Date.ISO8601FormatStyle(timeZone: timeZone).year().month().day()
        let time = Date.ISO8601FormatStyle(timeZoneSeparator: .colon, timeZone: timeZone)
        let rows = entries.map { entry in
            [
                entry.start.formatted(day),
                entry.start.formatted(time),
                entry.end?.formatted(time) ?? "",
                entry.end.map { String(Int(max(0, $0.timeIntervalSince(entry.start)) / 60)) } ?? "",
            ] + [
                entry.kindRaw,
                entry.workspace?.name ?? "",
                entry.project?.name ?? "",
                entry.note,
                entry.sourceRaw,
            ].map(text)
        }
        return "\u{FEFF}" + ([columns] + rows)
            .map { $0.map(field).joined(separator: ",") + "\r\n" }
            .joined()
    }

    /// `value` with a leading `'` when its first scalar would start a formula.
    ///
    /// The first scalar, not the first character, because `\r\n` is one
    /// character in Swift and must still count as a carriage return.
    private static func text(_ value: String) -> String {
        guard let first = value.unicodeScalars.first, "=+-@\t\r".unicodeScalars.contains(first) else { return value }
        return "'" + value
    }

    /// `value` quoted when it holds a comma, a quote or a line break.
    private static func field(_ value: String) -> String {
        guard value.contains(where: { $0 == "," || $0 == "\"" || $0.isNewline }) else { return value }
        return "\"\(value.replacingOccurrences(of: "\"", with: "\"\""))\""
    }
}
