import Foundation
import SwiftData

/// A stretch without input on the Mac, from the last input to the return,
/// that a block counted as work.
///
/// The app asks what it was and keeps the question in memory only, so a quit
/// drops it and the time counts as worked. See
/// ``TimerEngine/timeAway(since:returnedAt:threshold:)`` and
/// ``TimerEngine/settle(_:as:at:)``.
public struct TimeAway: Equatable, Sendable {
    /// How long without input before the app asks, in minutes, before the user changes it.
    public static let defaultThresholdMinutes = 10
    /// The thresholds the app accepts, in minutes.
    public static let thresholdRange = 1 ... 60
    /// How long after the last input an action it caused, such as a click on
    /// Pause or Break, may still end a work entry. A work entry that ended
    /// that soon did not run while he was away.
    static let inputSlack: TimeInterval = 1

    /// When the time away began: the last input, or the start of the work
    /// entry when that came later, such as after a break ran out.
    public let start: Date
    /// When he came back, never before ``start``.
    public let end: Date

    /// The time away from `start` to `end`, or of no length when `end` is earlier.
    public init(start: Date, end: Date) {
        self.start = start
        self.end = max(start, end)
    }

    /// How long he was away.
    public var length: TimeInterval {
        end.timeIntervalSince(start)
    }

    /// How long he was away, in whole minutes, rounded down after rounding to
    /// the nearest second, so the jitter of reading the idle time never takes
    /// a minute away.
    public var minutes: Int {
        MenuBarLabel.wholeSeconds(length.rounded()) / 60
    }

    /// The question once a later time away comes before the answer: from the
    /// earlier start to the later return.
    public func widened(by later: Self) -> Self {
        Self(start: min(start, later.start), end: max(end, later.end))
    }

    /// The threshold in minutes, read back from outside: `minutes` when it is
    /// in ``thresholdRange``, otherwise ``defaultThresholdMinutes``.
    public static func thresholdMinutes(remembered minutes: Int) -> Int {
        thresholdRange.contains(minutes) ? minutes : defaultThresholdMinutes
    }
}

/// What the time away was, as he answers.
public enum AwayAnswer: CaseIterable, Sendable {
    /// Work: the entries stay as they are.
    case work
    /// A meeting inside the block. The block's end does not move.
    case meeting
    /// A break inside the block, stopped at the block's end. The block's end does not move.
    case `break`
    /// Not tracked: the time counts like a pause, so a running block ends later by it.
    case discard
}

public extension TimerEngine {
    /// Settles at `returned`, then the time away from `lastInput` to
    /// `returned` that a block's work entry counted, or `nil` when it is
    /// shorter than `threshold` seconds.
    ///
    /// It starts at `lastInput`, or at the work entry's start when that came
    /// later, such as when a break ran out while he was away and work went on.
    /// Time on a break, paused or with nothing running is never part of it,
    /// so when no work entry ran between `lastInput` and `returned` there is
    /// nothing to ask. A work entry that `lastInput` itself ended, such as by
    /// a click on Pause or Break a moment before, did not run then. A block
    /// that ran out meanwhile still counts, up to its end.
    func timeAway(since lastInput: Date, returnedAt returned: Date, threshold: TimeInterval) throws -> TimeAway? {
        try settle(at: returned)
        guard let entry = try workEntry(from: lastInput, to: returned) else { return nil }
        let away = TimeAway(start: max(lastInput, entry.start), end: returned)
        return away.length >= threshold ? away : nil
    }

    /// Settles at `now`, then changes the entries of the block that counted
    /// `away` as work, as `answer` says.
    ///
    /// The work entry ends where the time away began. A meeting or a break
    /// then runs to the return, or to the block's end when that came first.
    /// Work goes on from the return while the block lasts: it runs on in a
    /// block that still runs, and ends where it ended in a block that ran out
    /// meanwhile. So the block's end never moves for a meeting or a break.
    /// After a discard the time away is a gap, which moves the end of a
    /// running block later by its length. A block that ran out while he was
    /// away then ends where the time away began, and one that ran out after
    /// his return stays ended where it was.
    ///
    /// Every new entry lies inside the one it replaces, or after the running
    /// one, so no two overlap. Work changes nothing, and so does a time away
    /// that no work entry counts any longer, such as after an edit. A `now`
    /// before the return, as after the clock moved back, is raised to it.
    func settle(_ away: TimeAway, as answer: AwayAnswer, at now: Date) throws {
        try settle(at: max(now, away.end))
        guard answer != .work, let entry = try workEntry(from: away.start, to: away.end),
              let block = entry.block
        else { return }
        let start = max(away.start, entry.start)
        let returned = max(away.end, start)
        let end = entry.end
        guard end.map({ $0 > start }) ?? true else { return }

        var parts = [AwayPart(kind: .work, start: entry.start, end: start)]
        switch answer {
        case .meeting: parts.append(AwayPart(kind: .meeting, start: start, end: min(returned, end ?? returned)))
        case .break: parts.append(AwayPart(kind: .break, start: start, end: min(returned, end ?? returned)))
        case .work, .discard: break
        }
        if end.map({ $0 > returned }) ?? true {
            parts.append(AwayPart(kind: .work, start: returned, end: end))
        }
        // An entry of no length would only clutter the day.
        parts.removeAll { part in part.end.map { $0 <= part.start } ?? false }

        guard let first = parts.first else {
            context.delete(entry)
            try context.save()
            return
        }
        entry.kind = first.kind
        entry.start = first.start
        entry.end = first.end
        for part in parts.dropFirst() {
            begin(part.kind, in: block, at: part.start).end = part.end
        }
        try context.save()
    }

    /// The timer's latest work entry that ran between `start` and `end`, or
    /// `nil` when none did or it belongs to no block. One that ended within
    /// ``TimeAway/inputSlack`` after `start` was ended by the input at `start`,
    /// so it did not run then.
    private func workEntry(from start: Date, to end: Date) throws -> TimeEntry? {
        let timer = TimeEntrySource.timer.rawValue
        let work = TimeEntryKind.work.rawValue
        let after = start.addingTimeInterval(TimeAway.inputSlack)
        var descriptor = FetchDescriptor<TimeEntry>(
            predicate: #Predicate { entry in
                if let entryEnd = entry.end {
                    entry.sourceRaw == timer && entry.kindRaw == work && entry.start < end && entryEnd > after
                } else {
                    entry.sourceRaw == timer && entry.kindRaw == work && entry.start < end
                }
            },
            sortBy: [SortDescriptor(\.start, order: .reverse)],
        )
        descriptor.fetchLimit = 1
        return try context.fetch(descriptor).first.flatMap { $0.block == nil ? nil : $0 }
    }
}

/// One entry as an answer about time away leaves it: running when `end` is `nil`.
private struct AwayPart {
    let kind: TimeEntryKind
    let start: Date
    let end: Date?
}
