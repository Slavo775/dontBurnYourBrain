import Foundation

/// One of the moments the timer announces with a sound and a notification.
public enum AlertKind: String, CaseIterable, Sendable {
    /// A block ran to its planned end.
    case blockEnd
    /// A break ran to its planned end, and work goes on.
    case breakEnd
    /// A block has ``warningLead`` left.
    case warning

    /// How long before a block's end the warning comes.
    public static let warningLead: TimeInterval = 5 * 60
    /// The longest a sound may come after its moment. A later one, such as
    /// after the Mac woke from sleep, is left out, because it would only confuse.
    public static let maximumSoundDelay: TimeInterval = 60

    /// The alert whose moment passed by itself between two settles, or `nil`.
    ///
    /// `previous` is the status settled at `then`, `current` the one settled
    /// at `now`, with no action of the user in between. A block that ran out
    /// wins over a break that ended at the same time, and both over the
    /// warning. A paused block never runs out, so it has none. A moment more
    /// than ``maximumSoundDelay`` before `now` gives none.
    public static func due(from previous: TimerStatus, at then: Date, to current: TimerStatus, at now: Date) -> Self? {
        guard previous.state == .working || previous.state == .onBreak, let end = previous.plannedEnd else {
            return nil
        }
        let earliest = max(then, now.addingTimeInterval(-maximumSoundDelay))
        func passed(_ moment: Date) -> Bool {
            moment > earliest && moment <= now
        }
        if passed(end), current.state == .idle {
            return .blockEnd
        }
        if previous.state == .onBreak, let left = previous.breakTimeLeft {
            let breakEnd = then.addingTimeInterval(left)
            if breakEnd < end, passed(breakEnd), current.state == .working {
                return .breakEnd
            }
        }
        if passed(end.addingTimeInterval(-warningLead)), current.state != .idle {
            return .warning
        }
        return nil
    }
}

/// Which alerts give a notification and which a sound.
public struct AlertSettings: Equatable, Sendable {
    /// The alerts that show a notification.
    public var notifications: Set<AlertKind>
    /// The alerts that play a sound.
    public var sounds: Set<AlertKind>

    /// The settings before the user changes any: the block's and the break's
    /// end give both, the warning gives neither.
    public static let standard = AlertSettings(notifications: [.blockEnd, .breakEnd], sounds: [.blockEnd, .breakEnd])

    /// Settings with `notifications` and `sounds` switched on.
    public init(notifications: Set<AlertKind>, sounds: Set<AlertKind>) {
        self.notifications = notifications
        self.sounds = sounds
    }
}

/// A notification that should be waiting to be shown at its moment.
public struct PlannedAlert: Equatable, Sendable {
    /// What it announces.
    public let kind: AlertKind
    /// When it is shown.
    public let date: Date
    /// The running block's workspace name, which the text names.
    public let workspace: String

    /// The notifications that should be waiting for `status` at `now`, in the order of ``AlertKind``.
    ///
    /// While working or on a break: the block's end at its planned end, the
    /// warning ``AlertKind/warningLead`` before it while that lies ahead, and
    /// on a break the break's end, unless the break is clipped at the block's
    /// end, which the block's end then announces alone. Paused or idle: none, since nothing
    /// runs out. Only the kinds switched on in `settings` are planned. One
    /// kind is planned at most once, so its notification can be replaced.
    public static func plan(
        for status: TimerStatus,
        workspace: String,
        settings: AlertSettings,
        at now: Date,
    ) -> [Self] {
        guard status.state == .working || status.state == .onBreak, let end = status.plannedEnd else { return [] }
        var dates: [AlertKind: Date] = [.blockEnd: end, .warning: end.addingTimeInterval(-AlertKind.warningLead)]
        if status.state == .onBreak, let left = status.breakTimeLeft, now.addingTimeInterval(left) < end {
            dates[.breakEnd] = now.addingTimeInterval(left)
        }
        return AlertKind.allCases.compactMap { kind in
            guard settings.notifications.contains(kind), let date = dates[kind], date > now else { return nil }
            return Self(kind: kind, date: date, workspace: workspace)
        }
    }
}
