@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// The Dev build's stand-ins for time away, the `away` scenario, and the
// threshold rules of `TimeAway`.

// MARK: - The threshold

@Test func `the threshold is ten minutes by default, within one minute to an hour`() {
    #expect(TimeAway.defaultThresholdMinutes == 10)
    #expect(TimeAway.thresholdRange == 1 ... 60)
}

@Test(arguments: [1, 2, 10, 59, 60])
func `a remembered threshold within the range is kept`(minutes: Int) {
    #expect(TimeAway.thresholdMinutes(remembered: minutes) == minutes)
}

@Test(arguments: [0, -1, 61, 600, Int.min, Int.max])
func `a remembered threshold outside the range falls back to ten minutes`(minutes: Int) {
    #expect(TimeAway.thresholdMinutes(remembered: minutes) == 10)
}

// MARK: - The threshold argument

@Test(arguments: [("1", 1), ("9", 9), ("10", 10), ("60", 60), ("05", 5), ("000060", 60)] as [(String, Int)])
func `the threshold argument reads ASCII digits from 1 to 60`(raw: String, minutes: Int) {
    #expect(AwayStandIn.thresholdMinutes(from: raw) == minutes)
}

@Test(arguments: [
    "0", "61", "100", "", "+5", "-5", " 5", "5 ", "5\n", "1.5", "1e1", "0x5", "five",
    // Arabic-Indic and fullwidth digits.
    "\u{663}", "\u{FF15}",
    // Seven characters, even though the number would fit.
    "0000005",
    String(repeating: "1", count: 100_000),
])
func `the threshold argument rejects anything else`(raw: String) {
    #expect(AwayStandIn.thresholdMinutes(from: raw) == nil)
}

// MARK: - The simulated idle time

@Test(arguments: [("1", 1), ("90", 90), ("120", 120), ("86400", 86400), ("000090", 90)] as [(String, Int)])
func `the idle cycle argument reads ASCII digits from one second to a day`(raw: String, seconds: Int) {
    #expect(AwayStandIn.idleCycle(from: raw) == seconds)
}

@Test(arguments: [
    "0", "86401", "999999", "", "+90", "-90", " 90", "90 ", "1.5", "\u{669}\u{660}", "\u{FF19}\u{FF10}",
    "0000090", String(repeating: "9", count: 100_000),
])
func `the idle cycle argument rejects anything else`(raw: String) {
    #expect(AwayStandIn.idleCycle(from: raw) == nil)
}

@Test func `the simulated idle time counts up within each cycle and drops to zero at its end`() {
    func idle(_ seconds: TimeInterval) -> TimeInterval {
        AwayStandIn.secondsSinceLastInput(at: nine.addingTimeInterval(seconds), launch: nine, cycle: 90)
    }

    #expect(idle(0) == 0)
    #expect(idle(30) == 30)
    #expect(idle(89.5) == 89.5)
    #expect(idle(90) == 0)
    #expect(idle(100) == 10)
    #expect(idle(90 * 1000 + 45) == 45)
}

@Test func `the simulated idle time is zero before the launch`() {
    #expect(AwayStandIn.secondsSinceLastInput(at: at(-1), launch: nine, cycle: 90) == 0)
    #expect(AwayStandIn.secondsSinceLastInput(at: at(-600), launch: nine, cycle: 90) == 0)
}

@Test(arguments: [0, -5])
func `a cycle below one second counts as one, so the reading never fails`(cycle: Int) {
    let idle = AwayStandIn.secondsSinceLastInput(at: nine.addingTimeInterval(2.5), launch: nine, cycle: cycle)
    #expect(idle == 0.5)
}

// MARK: - The away scenario

@Test func `the away scenario is named by its launch argument`() {
    #expect(TimerScenario(launchArgument: "away") == .away)
    #expect(TimerScenario(launchArgument: "Away") == nil)
}

@Test func `the away scenario runs Acme as running does and asks about 25 minutes from 32 to 7 minutes ago`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: nine)
    try TimerScenario.away.apply(to: context, now: nine)
    let engine = TimerEngine(context: context)
    let status = try engine.settle(at: nine)
    let workspace = try engine.runningWorkspace()
    let away = try #require(TimerScenario.away.timeAway(at: nine))

    #expect(MenuBarLabel(status: status, workspace: workspace, untrackedSince: nine, at: nine)
        == .running(name: "Acme", color: .teal, time: "1:24"))
    #expect(away == TimeAway(start: at(-32), end: at(-7)))
    #expect(away.minutes == 25)
}

@Test func `discarding the away scenario's question moves Acme's end 25 minutes later`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: nine)
    try TimerScenario.away.apply(to: context, now: nine)
    let engine = TimerEngine(context: context)
    let away = try #require(TimerScenario.away.timeAway(at: nine))

    try engine.settle(away, as: .discard, at: nine)

    #expect(try engine.settle(at: nine).blockTimeLeft == TimeInterval((84 + 25) * 60))
    let block = try #require(try engine.runningBlock())
    let acme = (block.entries ?? []).sorted { $0.start < $1.start }
    #expect(acme.map(\.start) == [at(-36), at(-7)])
    #expect(acme.map(\.end) == [at(-32), nil] as [Date?])
    #expect(acme.map(\.kind) == [.work, .work])
}

@Test(arguments: TimerScenario.allCases.filter { $0 != .away })
func `no other scenario has a question waiting`(scenario: TimerScenario) {
    #expect(scenario.timeAway(at: nine) == nil)
}
