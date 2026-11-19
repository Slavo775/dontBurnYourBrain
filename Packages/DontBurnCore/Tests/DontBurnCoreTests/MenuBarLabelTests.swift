@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

private func working(left: TimeInterval?) -> TimerStatus {
    TimerStatus(state: .working, plannedEnd: nil, blockTimeLeft: left, breakTimeLeft: nil)
}

private func onBreak(left: TimeInterval?) -> TimerStatus {
    TimerStatus(state: .onBreak, plannedEnd: nil, blockTimeLeft: 3600, breakTimeLeft: left)
}

private let paused = TimerStatus(state: .paused, plannedEnd: nil, blockTimeLeft: 3600, breakTimeLeft: nil)

private func label(_ status: TimerStatus, untrackedFor seconds: TimeInterval = 0) -> MenuBarLabel {
    let acme = Workspace(name: "Acme", color: .teal)
    return MenuBarLabel(status: status, workspace: acme, untrackedSince: nine.addingTimeInterval(-seconds), at: nine)
}

private func redraw(_ status: TimerStatus, untrackedFor seconds: TimeInterval = 0) -> TimeInterval {
    MenuBarLabel.nextRedraw(status: status, untrackedSince: nine.addingTimeInterval(-seconds), after: nine)
        .timeIntervalSince(nine)
}

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

// MARK: - The four states

@Test(arguments: [
    (5040.0, "1:24"), (7200, "2:00"), (7199.9, "1:59"), (3600, "1:00"), (3599.9, "0:59"),
    (300, "0:05"), (299.9, "4:59"), (299, "4:59"), (59.5, "0:59"), (1, "0:01"), (0.4, "0:00"), (0, "0:00"),
    (36000 + 300, "10:05"),
] as [(TimeInterval, String)])
func `a running block shows hours and minutes, and minutes and seconds below five minutes, rounded down`(
    left: TimeInterval, shown: String,
) {
    #expect(label(working(left: left)) == .running(name: "Acme", color: .teal, time: shown))
}

@Test func `a running block without a time left shows 0:00`() {
    #expect(label(working(left: nil)) == .running(name: "Acme", color: .teal, time: "0:00"))
}

@Test func `a paused block shows the name and the color only`() {
    #expect(label(paused) == .paused(name: "Acme", color: .teal))
}

@Test(arguments: [
    (252.0, "4:12"), (300, "5:00"), (299.9, "4:59"), (0.9, "0:00"), (0, "0:00"),
] as [(TimeInterval, String)])
func `a break shows minutes and seconds left, rounded down`(left: TimeInterval, shown: String) {
    #expect(label(onBreak(left: left)) == .onBreak(time: shown))
}

@Test func `a break without a planned length shows no time`() {
    #expect(label(onBreak(left: nil)) == .onBreak(time: nil))
}

@Test(arguments: [
    (0.0, "60:00"), (0.001, "59:59"), (45, "15:00"), (59, "1:00"), (60, "0:00"), (75, "0:00"),
] as [(Double, String)])
func `a break with nothing running shows the cup and minutes and seconds left, with no workspace`(
    minute: Double, shown: String,
) throws {
    let resting = try #require(IdleBreak(start: nine, end: at(60)))
    let now = at(minute)
    let result = MenuBarLabel(status: resting.status(at: now), workspace: nil, untrackedSince: nine, at: now)
    #expect(result == .onBreak(time: shown))
}

@Test(arguments: [
    (0.0, nil), (600, nil), (899.9, nil), (900, "0:15"), (959.9, "0:15"), (3660, "1:01"),
] as [(TimeInterval, String?)])
func `nothing running shows the untracked time only from 15 minutes on`(seconds: TimeInterval, shown: String?) {
    #expect(label(.idle, untrackedFor: seconds) == .idle(untracked: shown))
}

@Test func `an untracked start in the future shows nothing`() {
    #expect(label(.idle, untrackedFor: -3600) == .idle(untracked: nil))
}

@Test func `the workspace name is shortened in the label`() {
    let long = Workspace(name: "Acme Corporation International Holdings", color: .indigo)
    let shown = MenuBarLabel(status: paused, workspace: long, untrackedSince: nine, at: nine)
    #expect(shown == .paused(name: "Acme Corporatio…", color: .indigo))
}

@Test func `a running block without a workspace shows an empty name in teal`() {
    let shown = MenuBarLabel(status: working(left: 600), workspace: nil, untrackedSince: nine, at: nine)
    #expect(shown == .running(name: "", color: .teal, time: "0:10"))
}

// MARK: - Redrawing

@Test(arguments: [
    (3600.0, 0.001), (3630, 30.001), (5040, 0.001), (5059.5, 19.501), (300, 0.001), (359, 59.001),
    (299.9, 0.901), (299, 0.001), (1.25, 0.251), (0.5, 0.501), (0, 0.001),
] as [(TimeInterval, TimeInterval)])
func `a running block redraws just after its digits change`(left: TimeInterval, wait: TimeInterval) {
    #expect(abs(redraw(working(left: left)) - wait) < 1e-6)
}

@Test(arguments: [(252.25, 0.251), (300, 0.001), (0, 0.001)] as [(TimeInterval, TimeInterval)])
func `a break redraws every second`(left: TimeInterval, wait: TimeInterval) {
    #expect(abs(redraw(onBreak(left: left)) - wait) < 1e-6)
}

@Test(arguments: [(252.25, 0.251), (3600, 0.001), (0, 0.001)] as [(TimeInterval, TimeInterval)])
func `a break with nothing running redraws every second, and at once at its end`(
    left: TimeInterval, wait: TimeInterval,
) {
    let status = TimerStatus(state: .idleBreak, plannedEnd: nil, blockTimeLeft: nil, breakTimeLeft: left)
    #expect(abs(redraw(status, untrackedFor: 1234) - wait) < 1e-6)
}

@Test func `paused, a break without a length and a block without a time left redraw after a minute`() {
    #expect(redraw(paused) == 60)
    #expect(redraw(onBreak(left: nil)) == 60)
    #expect(redraw(working(left: nil)) == 60)
}

@Test(arguments: [
    (0.0, 60.0), (600, 60), (890, 10), (899.9, 0.1), (900, 60), (930, 30), (3659, 1),
] as [(TimeInterval, TimeInterval)])
func `nothing running redraws when the untracked time shows or its minute changes`(
    seconds: TimeInterval, wait: TimeInterval,
) {
    #expect(abs(redraw(.idle, untrackedFor: seconds) - wait) < 1e-6)
}

@Test func `the next redraw is always after now and never more than a minute away`() {
    var statuses: [TimerStatus] = [paused, .idle, working(left: nil), onBreak(left: nil)]
    for tenth in stride(from: 0.0, through: 7300, by: 0.7) {
        statuses.append(working(left: tenth))
        statuses.append(onBreak(left: tenth))
    }
    for status in statuses {
        for untracked in [0.0, 899.9, 900, 1234.5, -500] {
            let wait = redraw(status, untrackedFor: untracked)
            #expect(wait > 0 && wait <= 60, "\(status) waits \(wait)")
        }
    }
}

// MARK: - Damaged times

@Test func `whole seconds are zero for no number or a negative time, and capped at about 68 years`() {
    #expect(MenuBarLabel.wholeSeconds(.nan) == 0)
    #expect(MenuBarLabel.wholeSeconds(-.infinity) == 0)
    #expect(MenuBarLabel.wholeSeconds(-5) == 0)
    #expect(MenuBarLabel.wholeSeconds(0) == 0)
    #expect(MenuBarLabel.wholeSeconds(59.9) == 59)
    #expect(MenuBarLabel.wholeSeconds(TimeInterval(Int32.max)) == Int(Int32.max))
    #expect(MenuBarLabel.wholeSeconds(TimeInterval(Int32.max) + 1) == Int(Int32.max))
    #expect(MenuBarLabel.wholeSeconds(TimeInterval(Int.max) * 2) == Int(Int32.max))
    #expect(MenuBarLabel.wholeSeconds(.infinity) == Int(Int32.max))
}

@Test func `a damaged time shows as zero or at its cap and never stops the app`() {
    #expect(MenuBarLabel.hoursAndMinutes(1e300) == "596523:14")
    #expect(MenuBarLabel.hoursAndMinutes(.nan) == "0:00")
    #expect(MenuBarLabel.minutesAndSeconds(.infinity) == "35791394:07")
    #expect(MenuBarLabel.minutesAndSeconds(-.infinity) == "0:00")
    let endless = TimerStatus(state: .idleBreak, plannedEnd: nil, blockTimeLeft: nil, breakTimeLeft: 1e20)
    #expect(label(endless) == .onBreak(time: "35791394:07"))
    #expect(label(working(left: .infinity)) == .running(name: "Acme", color: .teal, time: "596523:14"))
    for status in [endless, working(left: .infinity), working(left: .nan), onBreak(left: .nan)] {
        let wait = redraw(status)
        #expect(wait > 0 && wait <= 60, "\(status) waits \(wait)")
    }
}

// MARK: - Where the untracked time starts

@Test func `with no entry the untracked time starts at the app's start`() throws {
    let desk = try Desk()
    let start = try MenuBarLabel.untrackedStart(in: desk.context, appStart: at(-30), now: nine, calendar: utc)
    #expect(start == at(-30))
}

@Test func `an app started yesterday counts from the start of today`() throws {
    let desk = try Desk()
    let start = try MenuBarLabel.untrackedStart(in: desk.context, appStart: at(-24 * 60), now: nine, calendar: utc)
    #expect(start == at(-9 * 60))
}

@Test func `an entry that ended yesterday counts from the start of today`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-11 * 60), end: at(-10 * 60)))
    try desk.context.save()
    let start = try MenuBarLabel.untrackedStart(in: desk.context, appStart: at(-12 * 60), now: nine, calendar: utc)
    #expect(start == at(-9 * 60))
}

@Test func `the latest entry that ended today by now counts, of any kind and source`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-120), end: at(-90)))
    let meeting = TimeEntry(workspace: desk.globex, start: at(-60), end: at(-20), kind: .meeting, source: .calendar)
    desk.context.insert(meeting)
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-80), end: at(-70), source: .manual))
    try desk.context.save()
    let start = try MenuBarLabel.untrackedStart(in: desk.context, appStart: at(-5), now: nine, calendar: utc)
    #expect(start == at(-20))
}

@Test func `an entry that ends after now and a running entry do not count`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-120), end: at(-90)))
    desk.context.insert(TimeEntry(workspace: desk.globex, start: at(-10), end: at(50), kind: .meeting))
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-5), end: nil))
    try desk.context.save()
    let start = try MenuBarLabel.untrackedStart(in: desk.context, appStart: at(-200), now: nine, calendar: utc)
    #expect(start == at(-90))
}

@Test func `an entry ending exactly now counts`() throws {
    let desk = try Desk()
    desk.context.insert(TimeEntry(workspace: desk.acme, start: at(-30), end: nine))
    try desk.context.save()
    let start = try MenuBarLabel.untrackedStart(in: desk.context, appStart: at(-60), now: nine, calendar: utc)
    #expect(start == nine)
}

@Test func `a block that ends returns the item to nothing running, with the untracked time from its end`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 6, at: nine)
    let ending = try desk.engine.settle(at: at(5.99))
    #expect(MenuBarLabel(status: ending, workspace: desk.acme, untrackedSince: nine, at: at(5.99))
        == .running(name: "Acme", color: .teal, time: "0:00"))

    let after = at(6) + 0.001
    let status = try desk.engine.settle(at: after)
    let since = try MenuBarLabel.untrackedStart(in: desk.context, appStart: nine, now: after, calendar: utc)
    #expect(try desk.engine.runningWorkspace() == nil)
    #expect(since == at(6))
    #expect(MenuBarLabel(status: status, workspace: nil, untrackedSince: since, at: after) == .idle(untracked: nil))
    #expect(MenuBarLabel(status: status, workspace: nil, untrackedSince: since, at: at(21)) == .idle(untracked: "0:15"))
}

// MARK: - Shortening the name

@Test(arguments: [
    ("Acme", "Acme"),
    ("", ""),
    ("Acme Corporation", "Acme Corporation"),
    ("Acme Corporations", "Acme Corporatio…"),
    ("Acme Web Desig Studio", "Acme Web Desig…"),
    ("Acme\nWeb", "Acme Web"),
    ("Acme\r\nWeb", "Acme Web"),
    ("\nAcme\n\n", "Acme"),
    ("  Acme  ", "Acme"),
    ("Personal 👩‍💻🇸🇰", "Personal 👩‍💻🇸🇰"),
    (String(repeating: "👩‍💻", count: 16), String(repeating: "👩‍💻", count: 16)),
    (String(repeating: "👩‍💻", count: 17), String(repeating: "👩‍💻", count: 15) + "…"),
] as [(String, String)])
func `a name is one line and at most 16 characters including the ellipsis`(name: String, shown: String) {
    let result = MenuBarLabel.shortened(name)
    #expect(result == shown)
    #expect(result.count <= MenuBarLabel.maximumNameLength)
    let isOneLine = !result.contains(where: \.isNewline)
    #expect(isOneLine)
}

// MARK: - The running workspace

@Test func `the running workspace follows start, switch, pause and end`() throws {
    let desk = try Desk()
    #expect(try desk.engine.runningWorkspace() == nil)
    try desk.engine.start(desk.acme, at: nine)
    #expect(try desk.engine.runningWorkspace() === desk.acme)
    try desk.engine.switchTo(desk.globex, at: at(10))
    #expect(try desk.engine.runningWorkspace() === desk.globex)
    try desk.engine.pause(at: at(20))
    #expect(try desk.engine.runningWorkspace() === desk.globex)
    try desk.engine.end(at: at(30))
    #expect(try desk.engine.runningWorkspace() == nil)
}

// MARK: - The launch-argument scenarios

@Test(arguments: [
    ("running", TimerScenario.running), ("ending", .ending), ("paused", .paused), ("break", .onBreak),
    ("idle", .idle), ("untracked", .untracked), ("idle-break", .idleBreak), ("long-name", .longName),
    ("short", .short),
] as [(String, TimerScenario)])
func `each scenario is named by its launch argument`(raw: String, scenario: TimerScenario) {
    #expect(TimerScenario(launchArgument: raw) == scenario)
}

@Test(arguments: [
    nil, "", "onBreak", "longName", "BREAK", " idle", "idle ", "runningrunningru", "runningrunningrun",
    String(repeating: "running", count: 10000),
] as [String?])
func `an unknown, empty or too long value names no scenario`(raw: String?) {
    #expect(TimerScenario(launchArgument: raw) == nil)
}

@Test(arguments: [
    (TimerScenario.running, MenuBarLabel.running(name: "Acme", color: .teal, time: "1:24")),
    (.ending, .running(name: "Acme", color: .teal, time: "3:27")),
    (.paused, .paused(name: "Acme", color: .teal)),
    (.onBreak, .onBreak(time: "4:12")),
    (.idle, .idle(untracked: nil)),
    (.untracked, .idle(untracked: "0:15")),
    (.longName, .running(name: "Acme Corporatio…", color: .teal, time: "1:24")),
    (.short, .running(name: "Acme", color: .teal, time: "0:06")),
] as [(TimerScenario, MenuBarLabel)])
func `each scenario puts the sample timer into its state`(scenario: TimerScenario, shown: MenuBarLabel) throws {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: nine)
    try scenario.apply(to: context, now: nine)

    let engine = TimerEngine(context: context)
    let status = try engine.settle(at: nine)
    let since = try MenuBarLabel.untrackedStart(in: context, appStart: nine, now: nine, calendar: utc)
    let result = try MenuBarLabel(status: status, workspace: engine.runningWorkspace(), untrackedSince: since, at: nine)
    #expect(result == shown)
    // Only timer entries must not overlap: the sample's calendar meeting may, see "Timer entries never overlap".
    let timer = try entries(context).filter { $0.source == .timer }
    for (earlier, later) in zip(timer, timer.dropFirst()) {
        #expect((earlier.end ?? .distantFuture) <= later.start)
    }
}

@Test func `the short scenario switches to seconds at five minutes left and ends at six`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: nine)
    try TimerScenario.short.apply(to: context, now: nine)
    let engine = TimerEngine(context: context)

    func shown(at instant: Date) throws -> MenuBarLabel {
        let status = try engine.settle(at: instant)
        let since = try MenuBarLabel.untrackedStart(in: context, appStart: nine, now: instant, calendar: utc)
        let workspace = try engine.runningWorkspace()
        return MenuBarLabel(status: status, workspace: workspace, untrackedSince: since, at: instant)
    }

    #expect(try shown(at: at(1)) == .running(name: "Acme", color: .teal, time: "0:05"))
    #expect(try shown(at: at(1) + 0.001) == .running(name: "Acme", color: .teal, time: "4:59"))
    #expect(try shown(at: at(6) - 0.5) == .running(name: "Acme", color: .teal, time: "0:00"))
    #expect(try shown(at: at(6)) == .idle(untracked: nil))
}

@Test func `a scenario on a store without workspaces changes nothing`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    try TimerScenario.running.apply(to: context, now: nine)
    #expect(try context.fetchCount(FetchDescriptor<TimeBlock>()) == 0)
    #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 0)
}
