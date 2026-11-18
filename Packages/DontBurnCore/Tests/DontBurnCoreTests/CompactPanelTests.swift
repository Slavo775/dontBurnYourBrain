@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

private func working(left: TimeInterval) -> TimerStatus {
    TimerStatus(state: .working, plannedEnd: nil, blockTimeLeft: left, breakTimeLeft: nil)
}

// MARK: - The countdown

@Test(arguments: [
    (3600.0, "1:00", ":00"),
    (3599.0, "59", ":59"),
    (3600.9, "1:00", ":00"),
    (3661.0, "1:01", ":01"),
    (59.0, "0", ":59"),
    (0.0, "0", ":00"),
    (-5.0, "0", ":00"),
    (36000.0, "10:00", ":00"),
])
func `the countdown shows hours and minutes from one hour on, minutes alone below it, seconds apart`(
    seconds: TimeInterval, large: String, small: String,
) {
    let (clock, rest) = CompactPanel.split(seconds)
    #expect(clock == large)
    #expect(rest == small)
}

// MARK: - What the panel shows

@Test func `nothing is shown while nothing runs`() throws {
    let desk = try Desk()
    let block = TimeBlock(workspace: desk.acme, plannedStart: nine, plannedMinutes: 60, state: .running)
    #expect(CompactPanel(status: .idle, block: block, tracked: 0) == nil)
    #expect(CompactPanel(status: working(left: 60), block: nil, tracked: 0) == nil)
}

@Test func `while working the panel shows the block's countdown and its planned length`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: nine)
    let status = try desk.engine.settle(at: at(36))

    let panel = try #require(CompactPanel(status: status, block: desk.engine.runningBlock(), tracked: 600))

    #expect(panel.name == "Acme")
    #expect(panel.color == .teal)
    #expect(panel.state == .working)
    #expect(panel.clock == "1:24")
    #expect(panel.seconds == ":00")
    #expect(panel.line == .leftOf("2:00"))
    #expect(abs(panel.progress - 0.3) < 1e-9)
    #expect(panel.trackedToday == "0:10")
}

@Test func `while paused the line says paused and the countdown stands still`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 120, at: nine)
    try desk.engine.pause(at: at(36))

    let early = try #require(try CompactPanel(
        status: desk.engine.settle(at: at(40)), block: desk.engine.runningBlock(), tracked: 0,
    ))
    let late = try #require(try CompactPanel(
        status: desk.engine.settle(at: at(50)), block: desk.engine.runningBlock(), tracked: 0,
    ))

    #expect(early.line == .paused)
    #expect(early.clock == "1:24")
    #expect(late.clock == early.clock)
    #expect(late.seconds == early.seconds)
    #expect(late.progress == early.progress)
}

@Test func `on a break the countdown counts the break and the line names the workspace to return to`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.globex, minutes: 120, at: nine)
    try desk.engine.startBreak(minutes: 5, at: at(30))

    let panel = try #require(try CompactPanel(
        status: desk.engine.settle(at: at(31.5)), block: desk.engine.runningBlock(), tracked: 0,
    ))

    #expect(panel.state == .onBreak)
    #expect(panel.clock == "3")
    #expect(panel.seconds == ":30")
    #expect(panel.line == .onBreak(returnTo: "Globex"))
}

@Test func `on a break without a planned length the countdown counts the block`() throws {
    let desk = try Desk()
    let block = TimeBlock(workspace: desk.acme, plannedStart: nine, plannedMinutes: 60, state: .running)
    let status = TimerStatus(state: .onBreak, plannedEnd: nil, blockTimeLeft: 1800, breakTimeLeft: nil)

    let panel = try #require(CompactPanel(status: status, block: block, tracked: 0))

    #expect(panel.clock == "30")
}

@Test func `a block without a workspace shows no name and the first color`() throws {
    let block = TimeBlock(workspace: nil, plannedStart: nine, plannedMinutes: 60, state: .running)
    let panel = try #require(CompactPanel(status: working(left: 60), block: block, tracked: 0))
    #expect(panel.name.isEmpty)
    #expect(panel.color == .teal)
}

@Test(arguments: [
    (60, 3600.0, 0.0),
    (60, 1800.0, 0.5),
    (60, 0.0, 1.0),
    (60, 9000.0, 0.0),
    (0, 600.0, 1.0),
    (-5, 600.0, 1.0),
])
func `progress stays between zero and one`(planned: Int, left: TimeInterval, expected: Double) throws {
    let block = TimeBlock(workspace: nil, plannedStart: nine, plannedMinutes: planned, state: .running)
    let panel = try #require(CompactPanel(status: working(left: left), block: block, tracked: 0))
    #expect(panel.progress == expected)
}

// MARK: - The next redraw

@Test func `nothing is redrawn while nothing runs or the block is paused`() {
    #expect(CompactPanel.nextRedraw(status: .idle, after: nine) == nil)
    let paused = TimerStatus(state: .paused, plannedEnd: nil, blockTimeLeft: 600, breakTimeLeft: nil)
    #expect(CompactPanel.nextRedraw(status: paused, after: nine) == nil)
}

@Test func `while working the panel redraws when the next second of the block passes`() throws {
    let next = try #require(CompactPanel.nextRedraw(status: working(left: 100.25), after: nine))
    let delay = next.timeIntervalSince(nine)
    #expect(delay > 0.25)
    #expect(delay < 0.3)
}

@Test func `on a break the panel redraws with the break's seconds, or the block's without a planned break`() throws {
    let onBreak = TimerStatus(state: .onBreak, plannedEnd: nil, blockTimeLeft: 100.75, breakTimeLeft: 50.5)
    let withBreak = try #require(CompactPanel.nextRedraw(status: onBreak, after: nine))
    #expect(withBreak.timeIntervalSince(nine) > 0.5)
    #expect(withBreak.timeIntervalSince(nine) < 0.55)

    let open = TimerStatus(state: .onBreak, plannedEnd: nil, blockTimeLeft: 100.75, breakTimeLeft: nil)
    let withoutBreak = try #require(CompactPanel.nextRedraw(status: open, after: nine))
    #expect(withoutBreak.timeIntervalSince(nine) > 0.75)
    #expect(withoutBreak.timeIntervalSince(nine) < 0.8)
}

@Test func `at zero the panel still redraws soon after`() throws {
    let next = try #require(CompactPanel.nextRedraw(status: working(left: 0), after: nine))
    #expect(next > nine)
    #expect(next.timeIntervalSince(nine) < 0.1)
}

// MARK: - Today's tracked total

@Test func `tracked today counts only the part of each entry since midnight and up to now`() throws {
    let desk = try Desk()
    let midnight = utc.startOfDay(for: nine)
    // 23:30 yesterday to 00:30 today: half an hour today.
    desk.context.insert(TimeEntry(
        workspace: desk.acme, start: midnight.addingTimeInterval(-1800), end: midnight.addingTimeInterval(1800),
    ))
    // Wholly yesterday.
    desk.context.insert(TimeEntry(
        workspace: desk.acme, start: midnight.addingTimeInterval(-7200), end: midnight.addingTimeInterval(-3600),
    ))
    // Running since 08:30: half an hour.
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-30), end: nil))
    // A meeting from 08:00 to 08:15, entered by hand: a quarter of an hour.
    desk.context.insert(TimeEntry(
        workspace: desk.globex, start: at(-60), end: at(-45), kind: .meeting, source: .manual,
    ))
    // A meeting later today has not happened yet.
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(60), end: at(90), kind: .meeting, source: .manual))
    // A meeting from 08:50 to 09:30 counts up to now only.
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-10), end: at(30), kind: .meeting, source: .manual))
    try desk.context.save()

    let tracked = try CompactPanel.trackedToday(in: desk.context, now: nine, calendar: utc)

    #expect(tracked == (30 + 30 + 15 + 10) * 60)
}

@Test func `tracked today counts a break only when its workspace counts breaks`() throws {
    let desk = try Desk()
    desk.globex.breaksCount = false
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-60), end: at(-50), kind: .break))
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-40), end: at(-35), kind: .break))
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-30), end: at(-20)))
    try desk.context.save()

    let tracked = try CompactPanel.trackedToday(in: desk.context, now: nine, calendar: utc)

    #expect(tracked == (10 + 10) * 60)
}

@Test func `tracked today is zero with no entries and just after midnight`() throws {
    let desk = try Desk()
    #expect(try CompactPanel.trackedToday(in: desk.context, now: nine, calendar: utc) == 0)

    let midnight = utc.startOfDay(for: nine)
    desk.context.insert(TimeEntry(workspace: desk.acme, start: midnight.addingTimeInterval(-3600), end: nil))
    try desk.context.save()
    #expect(try CompactPanel.trackedToday(in: desk.context, now: midnight, calendar: utc) == 0)
    #expect(try CompactPanel.trackedToday(in: desk.context, now: midnight.addingTimeInterval(60), calendar: utc) == 60)
}

@Test func `tracked today follows the calendar's time zone`() throws {
    let desk = try Desk()
    // 07:00 to 09:00 UTC. In UTC+3 today began at 21:00 UTC yesterday, so all of it counts.
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-120), end: nine))
    // 22:00 to 23:00 UTC yesterday: today in UTC+3, yesterday in UTC.
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-660), end: at(-600)))
    try desk.context.save()
    var plusThree = Calendar(identifier: .gregorian)
    plusThree.timeZone = try #require(TimeZone(secondsFromGMT: 3 * 3600))

    #expect(try CompactPanel.trackedToday(in: desk.context, now: nine, calendar: utc) == 120 * 60)
    #expect(try CompactPanel.trackedToday(in: desk.context, now: nine, calendar: plusThree) == 180 * 60)
}
