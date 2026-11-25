import Foundation

/// One of the moments the timer announces with a sound and a notification.
public enum AlertKind: String, CaseIterable, Sendable {
    /// A block ran to its planned end.
    case blockEnd
    /// A break ran to its planned end, and work goes on, or the block waits
    /// for Resume, or, after a break with no block, nothing runs.
    case breakEnd
    /// A focus interval ended while working, so a planned break is due.
    case focusEnd
    /// A block has ``warningLead`` left.
    case warning

    /// How long before a block's end the warning comes.
    public static let warningLead: TimeInterval = 5 * 60
    /// The longest a sound may come after its moment. A later one, such as
    /// after the Mac woke from sleep, is left out, because it would only confuse.
    public static let maximumSoundDelay: TimeInterval = 60

    /// The alert whose moment passed by itself between two settles, or `nil`.
    ///
    /// `previous` is the status settled at `then`, and `rhythm` where its block
    /// stood in its rhythm there, if it has one. `current` is the status
    /// settled at `now`, with no action of the user in between, so a block
    /// paused there was paused by its rhythm, when a break ended. A block that
    /// ran out wins over a break that ended at the same time, both over a
    /// focus interval that ended, and all three over the warning. A block
    /// paused at `then` never runs out, so it has none. A break with no block
    /// that ran out gives the break's end. A moment more than
    /// ``maximumSoundDelay`` before `now` gives none.
    public static func due(
        from previous: TimerStatus,
        rhythm: FocusRhythm? = nil,
        at then: Date,
        to current: TimerStatus,
        at now: Date,
    ) -> Self? {
        let earliest = max(then, now.addingTimeInterval(-maximumSoundDelay))
        func passed(_ moment: Date) -> Bool {
            moment > earliest && moment <= now
        }
        if previous.state == .idleBreak, let left = previous.breakTimeLeft {
            return passed(then.addingTimeInterval(left)) && current.state == .idle ? .breakEnd : nil
        }
        guard previous.state == .working || previous.state == .onBreak, let end = previous.plannedEnd else {
            return nil
        }
        if passed(end), current.state == .idle {
            return .blockEnd
        }
        if previous.state == .onBreak, let left = previous.breakTimeLeft {
            let breakEnd = then.addingTimeInterval(left)
            if breakEnd < end, passed(breakEnd), current.state == .working || current.state == .paused {
                return .breakEnd
            }
        }
        if let rhythm, current.state == .working, rhythm.comingBreaks.contains(where: { passed($0.start) }) {
            return .focusEnd
        }
        // A block its rhythm paused ends later, so its warning comes later too.
        if passed(end.addingTimeInterval(-warningLead)), current.state == .working || current.state == .onBreak {
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

    /// The settings before the user changes any: the block's, the break's and
    /// the focus interval's end give both, the warning gives neither.
    public static let standard = AlertSettings(
        notifications: [.blockEnd, .breakEnd, .focusEnd],
        sounds: [.blockEnd, .breakEnd, .focusEnd],
    )

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
    /// The running block's workspace name, which the text names, or `nil`
    /// for the end of a break with no block.
    public let workspace: String?
    /// The minutes of the break that becomes due, for ``AlertKind/focusEnd``, otherwise `nil`.
    public let breakMinutes: Int?
    /// Whether the block waits for Resume after the break that ends, for ``AlertKind/breakEnd``.
    public let waitsForResume: Bool

    init(
        kind: AlertKind, date: Date, workspace: String?, breakMinutes: Int? = nil, waitsForResume: Bool = false,
    ) {
        self.kind = kind
        self.date = date
        self.workspace = workspace
        self.breakMinutes = breakMinutes
        self.waitsForResume = waitsForResume
    }

    /// The notifications that should be waiting for `status` at `now`, in the order of ``AlertKind``.
    ///
    /// While working or on a break: the block's end at its planned end, the
    /// warning ``AlertKind/warningLead`` before it while that lies ahead, on a
    /// break the break's end, unless the break is clipped at the block's end,
    /// which the block's end then announces alone, and with a `rhythm` the end
    /// of the focus interval after which the next planned break is due, but
    /// while a break is due none until it is taken or skipped. On a break that
    /// leaves the block paused: the break's end alone, since the rest moves
    /// later. On a break with no block: the break's end alone, with no
    /// workspace. Paused or idle: none, since nothing runs out. Only the kinds
    /// switched on in `settings` are planned. One kind is planned at most once,
    /// so its notification can be replaced.
    public static func plan(
        for status: TimerStatus,
        rhythm: FocusRhythm? = nil,
        workspace: String,
        settings: AlertSettings,
        at now: Date,
    ) -> [Self] {
        if status.state == .idleBreak {
            guard settings.notifications.contains(.breakEnd), let left = status.breakTimeLeft, left > 0 else {
                return []
            }
            return [Self(kind: .breakEnd, date: now.addingTimeInterval(left), workspace: nil)]
        }
        guard status.state == .working || status.state == .onBreak, let end = status.plannedEnd else { return [] }
        let waits = status.state == .onBreak && rhythm?.pausesAfterBreak == true
        var dates: [AlertKind: Date] = [:]
        if status.state == .onBreak, let left = status.breakTimeLeft, now.addingTimeInterval(left) < end {
            dates[.breakEnd] = now.addingTimeInterval(left)
        }
        // Adding the next focus end takes the one just shown off the screen, so it waits while a break is due.
        let nextBreak = rhythm?.isBreakDue == false ? rhythm?.nextBreak : nil
        if !waits {
            dates[.blockEnd] = end
            dates[.warning] = end.addingTimeInterval(-AlertKind.warningLead)
            dates[.focusEnd] = nextBreak?.start
        }
        return AlertKind.allCases.compactMap { kind in
            guard settings.notifications.contains(kind), let date = dates[kind], date > now else { return nil }
            return Self(
                kind: kind,
                date: date,
                workspace: workspace,
                breakMinutes: kind == .focusEnd ? nextBreak.map(\.minutes) : nil,
                waitsForResume: kind == .breakEnd && waits,
            )
        }
    }
}
