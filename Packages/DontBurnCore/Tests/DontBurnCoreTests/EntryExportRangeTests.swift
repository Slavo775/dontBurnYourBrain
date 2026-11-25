@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// The starts of the entries `interval` exports, read at `now`.
private func exported(_ interval: DateInterval, from context: ModelContext, now: Date) throws -> [Date] {
    try EntryExport.entries(startingIn: interval, in: context, now: now).map(\.start)
}

private func interval(_ span: HistoryRange.Span, _ date: Date) -> DateInterval {
    let range = HistoryRange(span, containing: date, calendar: prague)
    return DateInterval(start: range.start, end: range.end)
}

@Test func `an entry belongs to the range it starts in, so neighbouring weeks never share one`() throws {
    let desk = try Desk()
    let starts = [
        // Starts before the week of 9 November and reaches into it.
        local(11, 8, 23, 30),
        // Ends exactly as the week of 16 November starts.
        local(11, 15, 23),
        // Starts exactly as that week starts.
        local(11, 16),
        // Crosses the midnight that ends that week.
        local(11, 22, 23, 30),
        local(11, 23, 0, 30),
    ]
    let ends = [local(11, 9, 0, 30), local(11, 16), local(11, 16, 0, 45), local(11, 23, 0, 30), local(11, 23, 1)]
    for (start, end) in zip(starts, ends) {
        try insert(desk.context, desk.acme, start, end)
    }
    let now = local(11, 25, 12)

    #expect(try exported(interval(.week, local(11, 9)), from: desk.context, now: now) == [starts[1]])
    #expect(try exported(interval(.week, local(11, 16)), from: desk.context, now: now) == [starts[2], starts[3]])
    #expect(try exported(interval(.week, local(11, 23)), from: desk.context, now: now) == [starts[4]])
    #expect(try exported(interval(.week, local(11, 2)), from: desk.context, now: now) == [starts[0]])
}

@Test func `consecutive days, weeks and months export every entry exactly once`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: friday)
    try SampleData.seedHistory(into: context, now: friday, calendar: prague)
    // Across the end of October. The sample history also holds the clocks going back on 25 October.
    try insert(context, nil, local(10, 31, 23), local(11, 1, 1))
    let everything = try entries(context).map(\.start)
    #expect(everything.first ?? .distantPast >= local(10, 16))

    let spans: [(Calendar.Component, Date)] = [(.day, local(9, 28)), (.weekOfYear, local(9, 28)), (.month, local(9, 1))]
    for (span, first) in spans {
        var starts: [Date] = []
        var from = first
        while from < friday {
            let next = prague.date(byAdding: span, value: 1, to: from) ?? .distantFuture
            starts += try exported(DateInterval(start: from, end: next), from: context, now: friday)
            from = next
        }
        #expect(starts == everything, "by \(span)")
    }
    #expect(try exported(interval(.month, local(10, 15)), from: context, now: friday).last == local(10, 31, 23))
}

@Test func `the export stops at now and holds the running entry, earliest first`() throws {
    let desk = try Desk()
    try insert(desk.context, desk.globex, local(11, 19, 9), local(11, 19, 10))
    try insert(desk.context, desk.globex, local(11, 20, 17), local(11, 20, 18), kind: .meeting, source: .calendar)
    try insert(desk.context, desk.globex, local(11, 16, 9), local(11, 16, 10))
    try desk.engine.start(desk.acme, minutes: 120, at: local(11, 20, 16))
    let week = interval(.week, friday)

    let starts = [local(11, 16, 9), local(11, 19, 9), local(11, 20, 16)]
    #expect(try exported(week, from: desk.context, now: friday) == starts)
    #expect(try exported(interval(.week, local(11, 23)), from: desk.context, now: friday).isEmpty)
    #expect(try exported(week, from: desk.context, now: local(11, 16, 9)).isEmpty)
}
