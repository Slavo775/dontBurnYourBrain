@testable import DontBurnCore
import Foundation
import Testing

// Card #58: the breaks a block's strip shows, the breaks that lie ahead, and
// whether the running break leaves the block waiting.

/// The breaks in the strip of Acme's running block at `now`, in minutes of the
/// block's own time, where `minutes` is the block's planned length.
private func gaps(_ desk: Desk, at now: Date, of minutes: Double) throws -> [[Double]] {
    let plannedEnd = try #require(try desk.engine.settle(at: now).plannedEnd)
    let rhythm = try checkedRhythm(desk.engine, at: now)
    let block = try #require(try desk.engine.runningBlock())
    return rhythm.breakFractions(of: block, plannedEnd: plannedEnd).map { gap in
        [gap.lowerBound, gap.upperBound].map { ($0 * minutes * 1000).rounded() / 1000 }
    }
}

/// A desk whose Acme follows a waiting 25/5 and runs a block of `minutes` from nine.
private func runningOnWaiting(minutes: Int = 60) throws -> Desk {
    let desk = try Desk()
    try desk.acmeFollows(waitingPreset())
    try desk.engine.start(desk.acme, minutes: minutes, at: nine)
    return desk
}

// MARK: - The gaps

@Test func `the strip shows every planned break, and none that the block's end leaves out`() throws {
    let desk = try runningOn25(minutes: 120)

    #expect(try gaps(desk, at: nine, of: 120) == [[25, 30], [55, 60], [85, 90]])
    #expect(try gaps(desk, at: at(24.9), of: 120) == [[25, 30], [55, 60], [85, 90]])
}

@Test func `a break that is due shows at its planned place and length`() throws {
    let desk = try runningOn25(minutes: 120)

    #expect(try gaps(desk, at: at(25), of: 120) == [[25, 30], [55, 60], [85, 90]])
    #expect(try gaps(desk, at: at(29.9), of: 120) == [[25, 30], [55, 60], [85, 90]])
}

@Test func `a skipped break leaves no gap, and the planned ones after it move with the focus`() throws {
    let desk = try runningOn25(minutes: 120)

    #expect(try gaps(desk, at: at(30), of: 120) == [[55, 60], [85, 90]])
    #expect(try gaps(desk, at: at(61), of: 120) == [[85, 90]])
}

@Test func `a taken break shows as long as it really lasted, where it was taken`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.startBreak(minutes: 5, at: at(27))
    try desk.engine.endBreak(at: at(29))

    #expect(try gaps(desk, at: at(36), of: 120) == [[27, 29], [54, 59], [84, 89]])
}

@Test func `a running break shows as far as it lasts, and one ended at once shows nothing`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.startBreak(minutes: 15, at: at(10))
    #expect(try gaps(desk, at: at(12), of: 120) == [[10, 25], [50, 55], [80, 85]])

    try desk.engine.endBreak(at: at(10))
    #expect(try gaps(desk, at: at(12), of: 120) == [[35, 40], [65, 70], [95, 110]])
}

@Test func `a pause does not count in the strip, before, during or after it`() throws {
    let desk = try runningOn25(minutes: 120)
    let planned = [[25.0, 30], [55, 60], [85, 90]]
    try desk.engine.pause(at: at(20))
    #expect(try gaps(desk, at: at(20), of: 120) == planned)
    #expect(try gaps(desk, at: at(45), of: 120) == planned)

    try desk.engine.resume(at: at(50))
    #expect(try gaps(desk, at: at(51), of: 120) == planned)
    try desk.engine.startBreak(minutes: 5, at: at(55))
    #expect(try gaps(desk, at: at(65), of: 120) == planned)
}

@Test func `a break that is due keeps its planned place and length while the block is paused`() throws {
    let desk = try runningOn25(minutes: 120)
    let planned = [[25.0, 30], [55, 60], [85, 90]]
    try desk.engine.pause(at: at(27))

    #expect(try gaps(desk, at: at(50), of: 120) == planned)
    try desk.engine.resume(at: at(90))
    #expect(try gaps(desk, at: at(91), of: 120) == planned)
    #expect(try gaps(desk, at: at(93), of: 120) == [[55, 60], [85, 90]])
}

@Test func `a pause during a break does not count, and the break shows only what was taken`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.startBreak(minutes: 5, at: at(25))
    try desk.engine.pause(at: at(27))

    #expect(try gaps(desk, at: at(40), of: 120) == [[25, 27], [52, 57], [82, 87]])
}

@Test func `+15 keeps the taken gaps where they are and brings the breaks of the longer block`() throws {
    let desk = try runningOn25(minutes: 60)
    try desk.engine.startBreak(minutes: 5, at: at(25))
    #expect(try gaps(desk, at: at(31), of: 60) == [[25, 30]])

    try desk.engine.extend(by: 15, at: at(31))

    #expect(try gaps(desk, at: at(31), of: 75) == [[25, 30], [55, 60]])
}

@Test func `+15 on a break lengthens its gap`() throws {
    let desk = try runningOn25(minutes: 60)
    try desk.engine.startBreak(minutes: 5, at: at(25))
    try desk.engine.extend(by: 15, at: at(27))

    #expect(try gaps(desk, at: at(28), of: 75) == [[25, 45]])
}

@Test func `a break the block's end cuts off reaches the end of the strip and not past it`() throws {
    let desk = try runningOn25(minutes: 60)
    try desk.engine.startBreak(minutes: 30, at: at(50))

    #expect(try gaps(desk, at: at(55), of: 60) == [[50, 60]])
}

@Test func `with the clock moved back before the block began the strip is the one at its start`() throws {
    let desk = try runningOn25(minutes: 120)

    #expect(try gaps(desk, at: at(-30), of: 120) == [[25, 30], [55, 60], [85, 90]])
}

@Test func `with the clock moved back behind a taken break the strip still shows it once`() throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.startBreak(minutes: 5, at: at(25))
    #expect(try desk.engine.settle(at: at(40)).state == .working)

    #expect(try gaps(desk, at: at(10), of: 120) == [[25, 30], [55, 60], [85, 90]])
}

@Test func `a break past the end of a block that was shortened is cut off at the strip's end`() throws {
    let desk = try runningOn25(minutes: 60)
    try desk.engine.startBreak(minutes: 5, at: at(25))
    let rhythm = try checkedRhythm(desk.engine, at: at(31))
    let block = try #require(try desk.engine.runningBlock())
    block.plannedMinutes = 28

    #expect(rhythm.breakFractions(of: block, plannedEnd: at(28)) == [25.0 / 28 ... 1])
}

@Test func `a block of no length has no gaps`() throws {
    let desk = try runningOn25(minutes: 60)
    let rhythm = try checkedRhythm(desk.engine, at: at(10))
    let empty = TimeBlock(workspace: desk.acme, plannedStart: nine, plannedMinutes: 0, state: .running)

    #expect(rhythm.breakFractions(of: empty, plannedEnd: nine).isEmpty)
}

@Test(arguments: [0.0, 10, 25, 27, 30, 45, 59.9])
func `every gap lies inside the strip, in order and apart`(minute: Double) throws {
    let desk = try runningOn25(minutes: 120)
    try desk.engine.startBreak(minutes: 5, at: at(minute))

    for later in [minute, minute + 1, minute + 6, 100, 119.9] {
        let shown = try gaps(desk, at: at(max(later, minute)), of: 120)
        for gap in shown {
            #expect(gap[0] >= 0 && gap[0] < gap[1] && gap[1] <= 120)
        }
        for (earlier, next) in zip(shown, shown.dropFirst()) {
            #expect(earlier[1] <= next[0])
        }
    }
}

// MARK: - The breaks ahead

@Test func `the coming breaks are the planned ones later than now, without the due or the running one`() throws {
    let desk = try runningOn25(minutes: 120)
    #expect(try checkedRhythm(desk.engine, at: at(10)).comingBreaks.map(\.start) == [at(25), at(55), at(85)])
    #expect(try checkedRhythm(desk.engine, at: at(27)).comingBreaks.map(\.start) == [at(55), at(85)])
    #expect(try checkedRhythm(desk.engine, at: at(31)).comingBreaks.map(\.start) == [at(55), at(85)])

    try desk.engine.startBreak(minutes: 5, at: at(55))
    #expect(try checkedRhythm(desk.engine, at: at(56)).comingBreaks.map(\.start) == [at(85)])
}

@Test func `no break comes when none fits before the block's end`() throws {
    #expect(try checkedRhythm(runningOn25(minutes: 30).engine, at: nine).comingBreaks.isEmpty)
    #expect(try checkedRhythm(runningOn25(minutes: 60).engine, at: at(31)).comingBreaks.isEmpty)
}

// MARK: - Waiting after the break

@Test func `a running break pauses the block at its end only with a preset that waits`() throws {
    let waiting = try runningOnWaiting()
    try waiting.engine.startBreak(minutes: 5, at: at(25))
    #expect(try checkedRhythm(waiting.engine, at: at(26)).pausesAfterBreak)
    #expect(try checkedRhythm(waiting.engine, at: at(29.9)).pausesAfterBreak)

    let resuming = try runningOn25()
    try resuming.engine.startBreak(minutes: 5, at: at(25))
    #expect(try !checkedRhythm(resuming.engine, at: at(26)).pausesAfterBreak)
}

@Test func `a break taken by hand waits too, and +15 on it keeps that`() throws {
    let desk = try runningOnWaiting(minutes: 120)
    try desk.engine.startBreak(minutes: 15, at: at(10))
    #expect(try checkedRhythm(desk.engine, at: at(12)).pausesAfterBreak)

    try desk.engine.extend(by: 15, at: at(12))

    let rhythm = try checkedRhythm(desk.engine, at: at(13))
    #expect(rhythm.pausesAfterBreak)
    #expect(rhythm.current == shortBreak(10, 40))
}

@Test(arguments: [50.0, 55, 58])
func `a break that reaches the block's end never waits, because the block is over then`(minute: Double) throws {
    let desk = try runningOnWaiting()
    let reachesEnd = Int(60 - minute)
    try desk.engine.startBreak(minutes: reachesEnd, at: at(minute))
    #expect(try !checkedRhythm(desk.engine, at: at(minute)).pausesAfterBreak)
    #expect(try desk.engine.settle(at: at(60)).state == .idle)

    let cutOff = try runningOnWaiting()
    try cutOff.engine.startBreak(minutes: 30, at: at(minute))
    #expect(try !checkedRhythm(cutOff.engine, at: at(minute)).pausesAfterBreak)
    #expect(try cutOff.engine.settle(at: at(60)).state == .idle)
}

@Test func `a break one minute short of the block's end waits`() throws {
    let desk = try runningOnWaiting()
    try desk.engine.startBreak(minutes: 9, at: at(50))

    #expect(try checkedRhythm(desk.engine, at: at(51)).pausesAfterBreak)
    #expect(try desk.engine.settle(at: at(59.5)).state == .paused)
}

@Test func `while working, due or paused no break is running, so none waits`() throws {
    let desk = try runningOnWaiting()
    #expect(try !checkedRhythm(desk.engine, at: at(10)).pausesAfterBreak)
    #expect(try !checkedRhythm(desk.engine, at: at(26)).pausesAfterBreak)
    try desk.engine.startBreak(minutes: 5, at: at(26))

    #expect(try desk.engine.settle(at: at(40)).state == .paused)
    #expect(try !checkedRhythm(desk.engine, at: at(40)).pausesAfterBreak)
}
