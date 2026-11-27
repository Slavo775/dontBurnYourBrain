@testable import DontBurnCore
import Foundation
import Testing

/// What `command` does in `state`, with a planned break of 10 minutes due
/// and 15 minutes as the last break length used.
private func outcome(_ command: BarCommand, in state: TimerState, due: Int? = 10, last: Int = 15) -> BarResult {
    command.result(in: state, dueBreakMinutes: due, lastBreakMinutes: last)
}

/// Checks `command` in every state against `expected`, so a state added
/// later fails here until it is given a row.
private func expect(
    _ command: BarCommand, _ expected: [TimerState: BarResult], sourceLocation: SourceLocation = #_sourceLocation,
) {
    for state in TimerState.allCases {
        #expect(outcome(command, in: state) == expected[state], "\(state)", sourceLocation: sourceLocation)
    }
}

@Test func `pause pauses a block or its break, resumes a paused one, and says why with no block`() {
    expect(.pause, [
        .working: BarResult(.pause),
        .paused: BarResult(.resume),
        .onBreak: BarResult(.pause),
        .idleBreak: BarResult(.pause, refusal: .noBlock),
        .idle: BarResult(.pause, refusal: .nothingRunning),
    ])
}

@Test func `resume works only while paused`() {
    expect(.resume, [
        .working: BarResult(.resume, refusal: .notPaused),
        .paused: BarResult(.resume),
        .onBreak: BarResult(.resume, refusal: .notPaused),
        .idleBreak: BarResult(.resume, refusal: .notPaused),
        .idle: BarResult(.resume, refusal: .nothingRunning),
    ])
}

@Test func `end ends any block and is refused with no block`() {
    expect(.end, [
        .working: BarResult(.endBlock),
        .paused: BarResult(.endBlock),
        .onBreak: BarResult(.endBlock),
        .idleBreak: BarResult(.endBlock, refusal: .noBlock),
        .idle: BarResult(.endBlock, refusal: .nothingRunning),
    ])
}

@Test func `plus 15 extends a block or any break and is refused with nothing running`() {
    expect(.extend, [
        .working: BarResult(.extend),
        .paused: BarResult(.extend),
        .onBreak: BarResult(.extend),
        .idleBreak: BarResult(.extend),
        .idle: BarResult(.extend, refusal: .nothingRunning),
    ])
}

@Test func `break with no length starts the due break, ends a running one, and does nothing while paused`() {
    expect(.takeBreak(minutes: nil), [
        .working: BarResult(.plannedBreak(minutes: 10)),
        .paused: BarResult(.startBreak(minutes: 15), refusal: .paused),
        .onBreak: BarResult(.endBreak),
        .idleBreak: BarResult(.endBreak),
        .idle: BarResult(.startBreak(minutes: 15)),
    ])
}

@Test func `break with no length and no break due starts one of the last length used`() {
    #expect(outcome(.takeBreak(minutes: nil), in: .working, due: nil, last: 30) == BarResult(.startBreak(minutes: 30)))
    #expect(outcome(.takeBreak(minutes: nil), in: .idle, due: nil, last: 5) == BarResult(.startBreak(minutes: 5)))
}

@Test func `break with a length starts that break unless paused or on a break`() {
    expect(.takeBreak(minutes: 10), [
        .working: BarResult(.startBreak(minutes: 10)),
        .paused: BarResult(.startBreak(minutes: 10), refusal: .paused),
        .onBreak: BarResult(.startBreak(minutes: 10), refusal: .onBreak),
        .idleBreak: BarResult(.startBreak(minutes: 10), refusal: .onBreak),
        .idle: BarResult(.startBreak(minutes: 10)),
    ])
}

@Test func `a typed break length wins over the due break`() {
    #expect(outcome(.takeBreak(minutes: 5), in: .working, due: 10) == BarResult(.startBreak(minutes: 5)))
}

@Test func `a break with nothing running is at most a day long, and inside a block it may be longer`() {
    #expect(outcome(.takeBreak(minutes: 1440), in: .idle) == BarResult(.startBreak(minutes: 1440)))
    #expect(outcome(.takeBreak(minutes: 1441), in: .idle) == BarResult(.startBreak(minutes: 1441), refusal: .tooLong))
    #expect(outcome(.takeBreak(minutes: 1441), in: .working) == BarResult(.startBreak(minutes: 1441)))
    // Paused says why first, and the length is not what is wrong.
    #expect(outcome(.takeBreak(minutes: 1441), in: .paused) == BarResult(.startBreak(minutes: 1441), refusal: .paused))
}

@Test func `a start is never refused and takes the workspace's default length when none is typed`() throws {
    let desk = try Desk()
    let (acme, globex, personal) = (desk.acme, desk.globex, desk.personal)
    for state in TimerState.allCases {
        #expect(outcome(.start(acme, minutes: nil), in: state) == BarResult(.start(acme, minutes: 60)))
        #expect(outcome(.start(personal, minutes: nil), in: state) == BarResult(.start(personal, minutes: 25)))
        #expect(outcome(.start(globex, minutes: 90), in: state) == BarResult(.start(globex, minutes: 90)))
    }
}

@Test func `what is typed reaches the right result in the timer's state`() throws {
    let desk = try Desk()
    let workspaces = [desk.acme, desk.globex, desk.personal]
    func results(_ text: String, _ state: TimerState) -> [BarResult] {
        BarCommand.commands(for: text, in: workspaces).map { outcome($0, in: state, due: nil) }
    }

    #expect(results("ac 2h", .working) == [BarResult(.start(desk.acme, minutes: 120))])
    #expect(results("p", .paused) == [BarResult(.resume), BarResult(.start(desk.personal, minutes: 25))])
    #expect(results("b", .paused) == [BarResult(.startBreak(minutes: 15), refusal: .paused)])
    #expect(results("break 10", .idle) == [BarResult(.startBreak(minutes: 10))])
    #expect(results("e", .idle) == [BarResult(.endBlock, refusal: .nothingRunning)])
    #expect(results("+15", .idleBreak) == [BarResult(.extend)])
    #expect(results("", .working).isEmpty)
}
