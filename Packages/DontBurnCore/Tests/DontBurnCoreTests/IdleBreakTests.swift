@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// Card #44 with nothing running: a break that no store holds, counts toward
// nothing, and ends by itself, by End break or by a block that starts.

private var utc: Calendar {
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .gmt
    return calendar
}

/// A break with nothing running from `start` to `end`, in minutes after nine.
private func idleBreak(_ start: Double, _ end: Double) throws -> IdleBreak {
    try #require(IdleBreak(start: at(start), end: at(end)))
}

// MARK: - Its span

@Test func `a break with nothing running may last from no time at all up to a day`() {
    #expect(IdleBreak(start: nine, end: nine) != nil)
    #expect(IdleBreak(start: nine, end: at(5)) != nil)
    #expect(IdleBreak(start: nine, end: nine.addingTimeInterval(IdleBreak.maximumLength)) != nil)
    #expect(IdleBreak.maximumLength == 24 * 60 * 60)
}

@Test func `a break with nothing running that ends before it starts or lasts more than a day is taken as damaged`() {
    #expect(IdleBreak(start: at(5), end: nine) == nil)
    #expect(IdleBreak(start: nine, end: nine.addingTimeInterval(-0.001)) == nil)
    #expect(IdleBreak(start: nine, end: nine.addingTimeInterval(IdleBreak.maximumLength + 0.001)) == nil)
    #expect(IdleBreak(start: .distantPast, end: .distantFuture) == nil)
}

@Test(arguments: [
    (0.0, 900.0), (2.5, 750), (14.99, 0.6), (15, 0), (16, 0), (-1, 960),
] as [(Double, TimeInterval)])
func `the time left counts down to zero at the end and never below`(minute: Double, left: TimeInterval) throws {
    #expect(try abs(idleBreak(0, 15).timeLeft(at: at(minute)) - left) < 1e-6)
}

@Test func `a break with nothing running is over exactly at its end`() throws {
    let resting = try idleBreak(0, 5)
    #expect(!resting.isOver(at: at(5).addingTimeInterval(-0.001)))
    #expect(resting.isOver(at: at(5)))
    #expect(resting.isOver(at: at(6)))
}

@Test(arguments: [
    (-5.0, 0.0), (0, 0), (3.75, 0.25), (7.5, 0.5), (15, 1), (40, 1),
] as [(Double, Double)])
func `the progress of a break with nothing running stays between zero and one`(
    minute: Double, progress: Double,
) throws {
    #expect(try idleBreak(0, 15).progress(at: at(minute)) == progress)
}

@Test func `a break with nothing running of no length is used up at once`() throws {
    #expect(try idleBreak(0, 0).progress(at: at(-1)) == 1)
}

@Test func `+15 moves the end of a break with nothing running fifteen minutes later and keeps its start`() throws {
    var resting = try idleBreak(0, 5)
    resting.extend(by: TimerEngine.defaultExtendMinutes)
    #expect(resting.start == nine)
    #expect(resting.end == at(20))
    #expect(resting.timeLeft(at: at(4)) == 16 * 60)
}

@Test func `the status of a break with nothing running has the break's time left and no block`() throws {
    #expect(try idleBreak(0, 15).status(at: at(2.5)) ==
        TimerStatus(state: .idleBreak, plannedEnd: nil, blockTimeLeft: nil, breakTimeLeft: 750))
    #expect(try idleBreak(0, 15).status(at: at(20)).breakTimeLeft == 0)
}

@Test func `a break with nothing running runs on only while nothing runs and it is not over`() throws {
    let resting = try idleBreak(0, 15)
    let block = TimerStatus(state: .working, plannedEnd: at(60), blockTimeLeft: 3000, breakTimeLeft: nil)
    let paused = TimerStatus(state: .paused, plannedEnd: at(60), blockTimeLeft: 3000, breakTimeLeft: nil)
    let onBreak = TimerStatus(state: .onBreak, plannedEnd: at(60), blockTimeLeft: 3000, breakTimeLeft: 300)

    #expect(resting.running(beside: .idle, at: at(10)) == resting)
    #expect(resting.running(beside: .idle, at: at(15)) == nil)
    for status in [block, paused, onBreak] {
        #expect(resting.running(beside: status, at: at(10)) == nil, "\(status.state) must win")
    }
}

// MARK: - Read back from outside, and once it stopped

@Test func `a break with nothing running ending up to a day ahead runs, one ending later is taken as damaged`() throws {
    let dayAhead = try #require(IdleBreak(start: nine, end: nine.addingTimeInterval(IdleBreak.maximumLength)))
    let pastADay = try #require(IdleBreak(
        start: nine.addingTimeInterval(1), end: nine.addingTimeInterval(IdleBreak.maximumLength + 1),
    ))

    #expect(dayAhead.running(beside: .idle, at: nine) == dayAhead)
    #expect(pastADay.running(beside: .idle, at: nine) == nil)
    #expect(pastADay.running(beside: .idle, at: nine.addingTimeInterval(1)) == pastADay)
}

@Test func `a break read back millions of years ahead neither runs nor counts as finished`() throws {
    let far = Date(timeIntervalSinceReferenceDate: 1e15)
    let damaged = try #require(IdleBreak(start: far, end: far.addingTimeInterval(3600)))

    #expect(damaged.running(beside: .idle, at: nine) == nil)
    #expect(damaged.ended(at: nine) == nil)
}

@Test func `a break with nothing running ended early finishes at that moment and keeps its start`() throws {
    #expect(try idleBreak(0, 15).ended(at: at(5)) == idleBreak(0, 5))
}

@Test func `a break with nothing running that ran out keeps its planned end`() throws {
    #expect(try idleBreak(0, 5).ended(at: at(5)) == idleBreak(0, 5))
    #expect(try idleBreak(0, 5).ended(at: at(40)) == idleBreak(0, 5))
}

@Test func `a break with nothing running ended by a block finishes where the block starts`() throws {
    let desk = try Desk()
    var resting: IdleBreak?
    try QuickAction.startBreak(minutes: 15, with: desk.engine, idleBreak: &resting, at: nine)
    let started = try #require(resting)

    try desk.engine.start(desk.globex, at: at(4))

    #expect(try started.running(beside: desk.engine.settle(at: at(4)), at: at(4)) == nil)
    #expect(try started.ended(at: at(4)) == idleBreak(0, 4))
}

@Test func `a break ending more than a day ahead is taken as damaged and does not finish`() throws {
    let ahead = try #require(IdleBreak(start: at(60), end: at(60).addingTimeInterval(IdleBreak.maximumLength)))
    #expect(ahead.ended(at: nine) == nil)
}

@Test func `a finished break read back after a restart stays finished with the same end`() throws {
    let finished = try idleBreak(40, 50)
    let readBack = try #require(IdleBreak(start: finished.start, end: finished.end))
    #expect(readBack.running(beside: .idle, at: at(90)) == nil)
    #expect(readBack.ended(at: at(90)) == finished)
}

// MARK: - Starting one

@Test(arguments: TimerEngine.breakLengthChoices)
func `a break with nothing running starts now with the chosen length and is stored nowhere`(minutes: Int) throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 30, at: nine)
    try desk.engine.end(at: at(20))
    let entriesBefore = try entries(desk.context).count
    var resting: IdleBreak?

    try QuickAction.startBreak(minutes: minutes, with: desk.engine, idleBreak: &resting, at: at(25))

    #expect(resting == IdleBreak(start: at(25), end: at(25 + Double(minutes))))
    #expect(try entries(desk.context).count == entriesBefore)
    #expect(try blocks(desk.context).map(\.state) == [.done])
    #expect(try desk.engine.settle(at: at(26)) == .idle)
}

@Test func `a break with nothing running starts on an empty store, as it needs no workspace`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    var resting: IdleBreak?

    try QuickAction.startBreak(minutes: 5, with: TimerEngine(context: context), idleBreak: &resting, at: nine)

    #expect(resting?.end == at(5))
    #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 0)
}

@Test func `a second break cannot start on a break with nothing running, which stays as it was`() throws {
    let desk = try Desk()
    var resting: IdleBreak? = try idleBreak(0, 15)

    #expect(throws: TimerEngineError.notAllowed(.idleBreak)) {
        try QuickAction.startBreak(minutes: 30, with: desk.engine, idleBreak: &resting, at: at(5))
    }

    #expect(try resting == idleBreak(0, 15))
}

@Test func `a new break with nothing running replaces one that is over`() throws {
    let desk = try Desk()
    var resting: IdleBreak? = try idleBreak(0, 5)

    try QuickAction.startBreak(minutes: 15, with: desk.engine, idleBreak: &resting, at: at(5))

    #expect(try resting == idleBreak(5, 20))
}

@Test(arguments: [0, -5, Int.min, 24 * 60 + 1, Int.max])
func `a break with nothing running of zero minutes or less, or longer than a day, is refused`(minutes: Int) throws {
    let desk = try Desk()
    var resting: IdleBreak?

    #expect(throws: TimerEngineError.invalidMinutes) {
        try QuickAction.startBreak(minutes: minutes, with: desk.engine, idleBreak: &resting, at: nine)
    }

    #expect(resting == nil)
}

@Test func `a break with nothing running of exactly a day is allowed`() throws {
    let desk = try Desk()
    var resting: IdleBreak?
    try QuickAction.startBreak(minutes: 24 * 60, with: desk.engine, idleBreak: &resting, at: nine)
    #expect(resting?.end == at(24 * 60))
}

// MARK: - The quick actions on it

@Test func `on a break with nothing running Pause is not offered, End break and +15 are`() {
    #expect(!QuickAction.pauseOrResume.isAvailable(in: .idleBreak))
    #expect(QuickAction.breakOrEndBreak.isAvailable(in: .idleBreak))
    #expect(QuickAction.extend.isAvailable(in: .idleBreak))
}

@Test func `ending a break with nothing running leaves nothing running and stores nothing`() throws {
    let desk = try Desk()
    var resting: IdleBreak? = try idleBreak(0, 15)

    try QuickAction.breakOrEndBreak.perform(with: desk.engine, idleBreak: &resting, at: at(3))

    #expect(resting == nil)
    #expect(try entries(desk.context).isEmpty)
    #expect(try desk.engine.settle(at: at(3)) == .idle)
}

@Test func `+15 lengthens a break with nothing running alone`() throws {
    let desk = try Desk()
    var resting: IdleBreak? = try idleBreak(0, 5)

    try QuickAction.extend.perform(with: desk.engine, idleBreak: &resting, at: at(3))
    try QuickAction.extend.perform(with: desk.engine, idleBreak: &resting, at: at(4))

    #expect(try resting == idleBreak(0, 35))
    #expect(try entries(desk.context).isEmpty)
    #expect(try blocks(desk.context).isEmpty)
}

@Test func `+15 on a break with nothing running is refused past a day, and the break stays as it was`() throws {
    let desk = try Desk()
    var resting: IdleBreak? = try idleBreak(0, 24 * 60 - 10)

    #expect(throws: TimerEngineError.invalidMinutes) {
        try QuickAction.extend.perform(with: desk.engine, idleBreak: &resting, at: at(60))
    }

    #expect(try resting == idleBreak(0, 24 * 60 - 10))
}

@Test func `+15 on a break with nothing running may reach exactly a day`() throws {
    let desk = try Desk()
    var resting: IdleBreak? = try idleBreak(0, 24 * 60 - 15)

    try QuickAction.extend.perform(with: desk.engine, idleBreak: &resting, at: at(60))

    #expect(try resting == idleBreak(0, 24 * 60))
}

@Test func `pausing a break with nothing running is refused and leaves it running`() throws {
    let desk = try Desk()
    var resting: IdleBreak? = try idleBreak(0, 15)

    #expect(throws: TimerEngineError.notAllowed(.idleBreak)) {
        try QuickAction.pauseOrResume.perform(with: desk.engine, idleBreak: &resting, at: at(3))
    }

    #expect(try resting == idleBreak(0, 15))
}

@Test func `a quick action after a break with nothing running ran out finds nothing running`() throws {
    let desk = try Desk()
    for action in QuickAction.allCases {
        var resting: IdleBreak? = try idleBreak(0, 5)
        #expect(throws: TimerEngineError.notAllowed(.idle)) {
            try action.perform(with: desk.engine, idleBreak: &resting, at: at(5))
        }
        #expect(resting == nil)
    }
}

@Test func `a quick action while a block runs acts on it and drops a leftover break with nothing running`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    var resting: IdleBreak? = try idleBreak(5, 20)

    try QuickAction.extend.perform(with: desk.engine, idleBreak: &resting, at: at(10))

    #expect(resting == nil)
    #expect(try blocks(desk.context).first?.plannedMinutes == 75)
}

@Test func `a block started on a break with nothing running ends that break`() throws {
    let desk = try Desk()
    var resting: IdleBreak?
    try QuickAction.startBreak(minutes: 15, with: desk.engine, idleBreak: &resting, at: nine)

    try desk.engine.start(desk.globex, at: at(4))

    #expect(try resting?.running(beside: desk.engine.settle(at: at(4)), at: at(4)) == nil)
    let all = try entries(desk.context)
    #expect(all.map(\.kind) == [.work])
    #expect(all.first?.start == at(4))
}

// MARK: - It counts toward nothing

@Test func `a break with nothing running leaves today's total and the entries as they were`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, minutes: 30, at: nine)
    try desk.engine.settle(at: at(30))
    let totalBefore = try CompactPanel.trackedToday(in: desk.context, now: at(30), calendar: utc)
    var resting: IdleBreak?

    try QuickAction.startBreak(minutes: 60, with: desk.engine, idleBreak: &resting, at: at(30))
    try QuickAction.extend.perform(with: desk.engine, idleBreak: &resting, at: at(40))
    try desk.engine.settle(at: at(110))

    #expect(try CompactPanel.trackedToday(in: desk.context, now: at(110), calendar: utc) == totalBefore)
    #expect(try DayLog(day: nine, in: desk.context, now: at(110), calendar: utc).total == 30 * 60)
    #expect(try entries(desk.context).map(\.kind) == [.work])
    #expect(try entries(desk.context).first?.end == at(30))
}

// MARK: - The sample scenario

@Test func `the idle-break scenario has nothing running and a 15 minute break with 12:30 left`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: nine)
    try TimerScenario.idleBreak.apply(to: context, now: nine)
    let engine = TimerEngine(context: context)

    let resting = try #require(TimerScenario.idleBreak.idleBreak(at: nine))
    let status = try engine.settle(at: nine)
    #expect(status == .idle)
    #expect(resting.start == at(-2.5))
    #expect(resting.end.timeIntervalSince(resting.start) == 15 * 60)
    #expect(resting.running(beside: status, at: nine) == resting)
    let label = MenuBarLabel(status: resting.status(at: nine), workspace: nil, untrackedSince: nine, at: nine)
    #expect(label == .onBreak(time: "12:30"))
    let lastTimerEnd = try entries(context).filter { $0.source == .timer }.compactMap(\.end).max()
    #expect(lastTimerEnd == resting.start)
}

@Test(arguments: TimerScenario.allCases.filter { $0 != .idleBreak })
func `no other scenario has a break with nothing running`(scenario: TimerScenario) {
    #expect(scenario.idleBreak(at: nine) == nil)
}
