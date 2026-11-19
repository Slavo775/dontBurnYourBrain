import Foundation
import SwiftData

/// A state of the timer the sample data can be put into, for screenshots and
/// for watching a short block on the live clock.
///
/// Every scenario is laid out relative to the `now` it is given, so with a
/// fixed time it looks the same on every launch.
public enum TimerScenario: String, CaseIterable, Sendable {
    /// Acme runs with 1:24 left.
    case running
    /// Acme runs with 3:27 left, in the last five minutes.
    case ending
    /// Acme is paused with 1:24 left.
    case paused
    /// Acme is on a break with 4:12 of it left.
    case onBreak = "break"
    /// Nothing runs, and the last block ended ten minutes ago.
    case idle
    /// Nothing runs, and the last block ended 15 minutes ago.
    case untracked
    /// Nothing runs, and a 15-minute break with no block has 12:30 left. Acme's
    /// block ended when the break started. See ``idleBreak(at:)``.
    case idleBreak = "idle-break"
    /// Acme runs with 1:24 left under a very long name.
    case longName = "long-name"
    /// Acme runs a six-minute block that starts at `now`, to watch on the
    /// live clock through the switch to seconds and to its end.
    case short

    /// The scenario a launch argument's value names, such as `break` in
    /// `-DontBurnTimerState break`.
    ///
    /// The value is input from outside the app. Anything but one of the raw
    /// values, exactly, is `nil`.
    public init?(launchArgument raw: String?) {
        guard let raw, raw.utf8.count <= 16 else { return nil }
        self.init(rawValue: raw)
    }

    /// Puts the timer in `context` into this scenario at `now` and saves.
    ///
    /// Expects the sample set from ``SampleData/seed(into:now:)`` and works
    /// through ``TimerEngine``, so the blocks and entries are the ones a
    /// user's own steps would leave.
    public func apply(to context: ModelContext, now: Date) throws {
        func ago(_ seconds: TimeInterval) -> Date {
            now.addingTimeInterval(-seconds)
        }

        let engine = TimerEngine(context: context)
        let workspaces = try context.fetch(FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.sortOrder)]))
        guard let acme = workspaces.first else { return }
        switch self {
        case .running:
            try engine.start(acme, minutes: 120, at: ago(36 * 60))
        case .ending:
            try engine.start(acme, minutes: 60, at: ago(60 * 60 - 207))
        case .paused:
            try engine.start(acme, minutes: 120, at: ago(46 * 60))
            try engine.pause(at: ago(10 * 60))
        case .onBreak:
            try engine.start(acme, minutes: 120, at: ago(40 * 60))
            try engine.startBreak(minutes: 5, at: ago(48))
        case .idle:
            try engine.start(acme, minutes: 30, at: ago(40 * 60))
        case .untracked:
            try engine.start(acme, minutes: 20, at: ago(35 * 60))
        case .idleBreak:
            try engine.start(acme, minutes: 120, at: ago(40 * 60))
            try engine.end(at: ago(150))
        case .longName:
            acme.name = "Acme Corporation International Holdings"
            try engine.start(acme, minutes: 120, at: ago(36 * 60))
        case .short:
            try engine.start(acme, minutes: 6, at: now)
        }
        try engine.settle(at: now)
    }

    /// The break with no block this scenario runs at `now`, or `nil`.
    ///
    /// Nothing stores that break, so ``apply(to:now:)`` cannot put it in the
    /// store. The app keeps it in memory.
    public func idleBreak(at now: Date) -> IdleBreak? {
        guard self == .idleBreak else { return nil }
        return IdleBreak(start: now.addingTimeInterval(-150), end: now.addingTimeInterval(750))
    }
}
