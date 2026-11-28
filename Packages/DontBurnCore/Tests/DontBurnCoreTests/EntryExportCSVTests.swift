@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

private let header = "date,start,end,minutes,kind,workspace,project,note,source\r\n"

/// The fields before the note of an Acme entry from 09:00 to 10:00 on Tuesday 17 November in Prague.
private let opening = "2026-11-17,2026-11-17T09:00:00+01:00,2026-11-17T10:00:00+01:00,60,work,Acme,,"

private func csv(_ entries: [TimeEntry], timeZone: TimeZone = prague.timeZone) -> String {
    EntryExport.csv(entries, timeZone: timeZone)
}

/// An Acme entry from 09:00 to 10:00 on Tuesday 17 November in Prague, with `note`.
private func noted(_ note: String, in desk: Desk) throws -> TimeEntry {
    try insert(desk.context, desk.acme, local(11, 17, 9), local(11, 17, 10), note: note)
}

/// The records of `text` read as a spreadsheet reads RFC 4180, after a
/// leading byte-order mark. Only a CRLF outside quotes ends a record.
private func records(_ text: String) -> [[String]] {
    var records: [[String]] = []
    var record: [String] = []
    var field = ""
    var quoted = false
    var rest = text.unicodeScalars[...]
    if rest.first == "\u{FEFF}" {
        rest.removeFirst()
    }
    while let scalar = rest.popFirst() {
        if quoted, scalar == "\"", rest.first == "\"" {
            rest.removeFirst()
            field.unicodeScalars.append(scalar)
        } else if scalar == "\"", quoted || field.isEmpty {
            quoted.toggle()
        } else if !quoted, scalar == "," {
            record.append(field)
            field = ""
        } else if !quoted, scalar == "\r", rest.first == "\n" {
            rest.removeFirst()
            records.append(record + [field])
            record = []
            field = ""
        } else {
            field.unicodeScalars.append(scalar)
        }
    }
    return records
}

// MARK: - The byte-order mark

@Test func `the text starts with one byte-order mark, then the header row, with or without entries`() throws {
    let desk = try Desk()
    let entry = try noted("Daily", in: desk)

    let text = csv([entry])

    #expect(csv([]) == "\u{FEFF}" + header)
    #expect(Array(text.utf8.prefix(3)) == [0xEF, 0xBB, 0xBF])
    #expect(text.unicodeScalars.count { $0 == "\u{FEFF}" } == 1)
    #expect(text == "\u{FEFF}" + header + opening + "Daily,timer\r\n")
}

@Test func `the sample week saved as UTF-8 holds the mark once and reads back one record per entry`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: friday)
    try SampleData.seedHistory(into: context, now: friday, calendar: prague)
    let week = HistoryRange(.week, containing: friday, calendar: prague)
    let entries = try EntryExport.entries(
        startingIn: DateInterval(start: week.start, end: week.end), in: context, now: friday,
    )
    try #require(entries.count > 10)

    try withTemporaryFolder { folder in
        let url = folder.url.appending(path: "2026-11-16–2026-11-22.csv")
        // As History's Export writes it.
        try EntryExport.csv(entries, timeZone: prague.timeZone).write(to: url, atomically: true, encoding: .utf8)
        let bytes = try Data(contentsOf: url)
        let read = try records(#require(String(bytes: bytes, encoding: .utf8)))

        #expect(Array(bytes.prefix(7)) == [0xEF, 0xBB, 0xBF] + Array("date".utf8))
        #expect(read.first == EntryExport.columns)
        #expect(read.count == entries.count + 1)
        for (record, entry) in zip(read.dropFirst(), entries) {
            #expect(record.count == 9)
            #expect(record[4] == entry.kindRaw)
            #expect(record[5] == entry.workspace?.name)
            #expect(record[6] == entry.project?.name ?? "")
            #expect(record[7] == entry.note)
        }
        #expect(read.contains { $0[7] == "Checkout, \"the redirect\" again\nthen the notes" })
        // Across midnight, once, with its start's date and all its minutes.
        #expect(read.filter { $0[0] == "2026-11-17" && $0[3] == "90" && $0[1].hasSuffix("T23:15:00+01:00") }.count == 1)
    }
}

// MARK: - The fields

@Test func `a row holds the start's date, ISO 8601 times with the offset, whole minutes and stored values`() throws {
    let desk = try Desk()
    let webShop = Project(name: "Web shop", workspace: desk.acme)
    desk.context.insert(webShop)
    let winter = try insert(
        desk.context, desk.acme, local(11, 17, 9), local(11, 17, 10, 30, second: 59), project: webShop, note: "Daily",
    )
    let summer = try insert(
        desk.context, desk.globex, local(7, 1, 8), local(7, 1, 8, 45), kind: .meeting, source: .calendar,
    )

    #expect(csv([winter, summer]) == "\u{FEFF}" + header
        + "2026-11-17,2026-11-17T09:00:00+01:00,2026-11-17T10:30:59+01:00,90,work,Acme,Web shop,Daily,timer\r\n"
        + "2026-07-01,2026-07-01T08:00:00+02:00,2026-07-01T08:45:00+02:00,45,meeting,Globex,,,calendar\r\n")
}

@Test func `the date and times follow the time zone given, with Z at UTC, and are never guarded`() throws {
    let desk = try Desk()
    // 00:30 on Tuesday in Prague is still Monday in UTC and in New York.
    let entry = try insert(desk.context, desk.acme, local(11, 17, 0, 30), local(11, 17, 1, 15))
    let newYork = try #require(TimeZone(identifier: "America/New_York"))
    let utc = "2026-11-16,2026-11-16T23:30:00Z,2026-11-17T00:15:00Z,45,work,Acme,,,timer\r\n"
    // The offset's minus is inside the field, so it is no formula and gets no quote mark.
    let west = "2026-11-16,2026-11-16T18:30:00-05:00,2026-11-16T19:15:00-05:00,45,work,Acme,,,timer\r\n"

    #expect(csv([entry], timeZone: .gmt) == "\u{FEFF}" + header + utc)
    #expect(csv([entry], timeZone: newYork) == "\u{FEFF}" + header + west)
}

@Test func `an entry across midnight has its start's date and all its minutes, rounded down`() throws {
    let desk = try Desk()
    let entry = try insert(desk.context, desk.personal, local(11, 17, 23, 15), local(11, 18, 0, 45, second: 59))

    #expect(csv([entry]).hasSuffix(
        "\r\n2026-11-17,2026-11-17T23:15:00+01:00,2026-11-18T00:45:59+01:00,90,work,Personal,,,timer\r\n",
    ))
}

@Test func `the running entry has an empty end and empty minutes`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: local(11, 20, 16))
    let running = try #require(try entries(desk.context).first)

    #expect(csv([running]).hasSuffix("\r\n2026-11-20,2026-11-20T16:00:00+01:00,,,work,Acme,,,timer\r\n"))
}

// MARK: - Quoting and the formula guard

@Test func `commas, quotes and line breaks are quoted, with quotes doubled, and read back as written`() throws {
    let desk = try Desk()
    desk.acme.name = "Acme, \"West\""
    let webShop = Project(name: "Web shop, v2", workspace: desk.acme)
    desk.context.insert(webShop)
    let notes = ["Checkout, \"the redirect\" again\nthen the notes", "one\r\ntwo", "carriage\rreturn", "plain"]
    let all = try notes.enumerated().map { index, note in
        try insert(
            desk.context, desk.acme, local(11, 17, 9 + index), local(11, 17, 10 + index), project: webShop, note: note,
        )
    }

    let text = csv(all)
    let read = records(text)

    let names = ",work,\"Acme, \"\"West\"\"\",\"Web shop, v2\","
    #expect(text.contains(names + "\"Checkout, \"\"the redirect\"\" again\nthen the notes\",timer\r\n"))
    #expect(text.contains(",\"one\r\ntwo\",timer\r\n"))
    #expect(text.contains(",\"carriage\rreturn\",timer\r\n"))
    #expect(text.contains(",plain,timer\r\n"))
    #expect(read.count == 5)
    #expect(read.allSatisfy { $0.count == 9 })
    #expect(read.dropFirst().map { $0[7] } == notes)
    #expect(read.dropFirst().allSatisfy { $0[5] == "Acme, \"West\"" && $0[6] == "Web shop, v2" })
}

@Test(arguments: zip(
    ["=SUM(A1)", "+1", "-1", "@cmd", "\tx", "\rx", "\r\nx", "=a,b", "-\"q\""],
    ["'=SUM(A1)", "'+1", "'-1", "'@cmd", "'\tx", "\"'\rx\"", "\"'\r\nx\"", "\"'=a,b\"", "\"'-\"\"q\"\"\""],
))
func `a note that starts like a formula gets a leading quote mark, then is quoted as needed`(
    note: String, field: String,
) throws {
    let desk = try Desk()
    let text = try csv([noted(note, in: desk)])

    #expect(text == "\u{FEFF}" + header + opening + field + ",timer\r\n")
    #expect(records(text).last?[7] == "'" + note)
}

@Test(arguments: zip(
    ["\nx", "a=b", "x+-@", "Acme", "Café résumé", "", "'=x", " =1"],
    ["\"\nx\"", "a=b", "x+-@", "Acme", "Café résumé", "", "'=x", " =1"],
))
func `a note that does not start like a formula is left as it is`(note: String, field: String) throws {
    let desk = try Desk()
    let text = try csv([noted(note, in: desk)])

    #expect(text == "\u{FEFF}" + header + opening + field + ",timer\r\n")
    #expect(records(text).last?[7] == note)
}

@Test func `a workspace, project, kind or source that starts like a formula is guarded too`() throws {
    let desk = try Desk()
    desk.acme.name = "=Acme"
    let webShop = Project(name: "@Web shop, v2", workspace: desk.acme)
    desk.context.insert(webShop)
    let entry = try insert(desk.context, desk.acme, local(11, 17, 9), local(11, 17, 10), project: webShop)
    entry.kindRaw = "+work"
    entry.sourceRaw = "-timer"

    #expect(csv([entry]).hasSuffix(",60,'+work,'=Acme,\"'@Web shop, v2\",,'-timer\r\n"))
}
