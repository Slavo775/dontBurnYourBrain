@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// Ten minutes, the default threshold, in seconds.
let tenMinutes = TimeInterval(TimeAway.defaultThresholdMinutes * 60)

/// One entry as the answer tests compare it: its kind and its span, running when `end` is `nil`.
struct Piece: Equatable, Sendable, CustomTestStringConvertible {
    let kind: TimeEntryKind
    let start: Date
    let end: Date?

    var testDescription: String {
        func minutes(_ date: Date) -> String {
            "\(Int(date.timeIntervalSince(nine) / 60))"
        }
        return "\(kind) \(minutes(start))–\(end.map(minutes) ?? "…")"
    }
}

/// What an answer leaves: the entries, and the block's planned end in minutes after nine.
struct Outcome: Sendable, CustomTestStringConvertible {
    let answer: AwayAnswer
    let pieces: [Piece]
    let end: Double

    init(_ answer: AwayAnswer, _ pieces: [Piece], endsAt end: Double) {
        self.answer = answer
        self.pieces = pieces
        self.end = end
    }

    var testDescription: String {
        "\(answer)"
    }
}

/// Work from `start` to `end` minutes after nine, or running on.
func work(_ start: Double, _ end: Double?) -> Piece {
    Piece(kind: .work, start: at(start), end: end.map(at))
}

/// A meeting from `start` to `end` minutes after nine.
func meeting(_ start: Double, _ end: Double) -> Piece {
    Piece(kind: .meeting, start: at(start), end: at(end))
}

/// A break from `start` to `end` minutes after nine.
func breakPiece(_ start: Double, _ end: Double) -> Piece {
    Piece(kind: .break, start: at(start), end: at(end))
}

/// Every entry in the store as a piece, earliest first.
func pieces(_ context: ModelContext) throws -> [Piece] {
    try entries(context).map { Piece(kind: $0.kind, start: $0.start, end: $0.end) }
}

/// The time away from `start` to `end` minutes after nine.
func away(_ start: Double, _ end: Double) -> TimeAway {
    TimeAway(start: at(start), end: at(end))
}

extension TimerEngine {
    /// Settles once a minute from `start` to `end` minutes after nine, as the
    /// app's countdown does while he is away and the Mac is awake.
    func tick(from start: Double, to end: Double) throws {
        for minute in stride(from: start, through: end, by: 1) {
            try settle(at: at(minute))
        }
    }

    /// Asks about the time away from `lastInput` to `returned` minutes after
    /// nine, with the default threshold, as the app does on his return.
    func ask(since lastInput: Double, returnedAt returned: Double) throws -> TimeAway? {
        try timeAway(since: at(lastInput), returnedAt: at(returned), threshold: tenMinutes)
    }
}

/// How the time away came about: idle while the Mac stayed awake and the
/// countdown settled every minute, or asleep, when nothing settled until waking.
enum Absence: CaseIterable, Sendable {
    case idle
    case sleep
}

/// Asks about the time away from `lastInput` to `returned` minutes after nine
/// as `absence` brings it, and expects a question for that span.
func askedAway(
    _ desk: Desk, since lastInput: Double, returnedAt returned: Double, by absence: Absence,
    sourceLocation: SourceLocation = #_sourceLocation,
) throws -> TimeAway {
    if absence == .idle {
        try desk.engine.tick(from: lastInput, to: returned)
    }
    return try #require(try desk.engine.ask(since: lastInput, returnedAt: returned), sourceLocation: sourceLocation)
}
