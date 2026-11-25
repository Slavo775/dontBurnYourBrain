import AppKit
import DontBurnCore
import os
import SwiftData
import SwiftUI

/// The timer's state for the menu bar item and the panel, renewed exactly
/// when what they show changes, and the one way the interface acts on the timer.
///
/// Each tick settles the timer engine, so a block whose time is up closes and
/// the item returns to the outline dot. The item and the panel read the same
/// settled state. Beside the engine it keeps the latest break with nothing
/// running (``IdleBreak``) and the last break length, which no store holds. While
/// the panel is open the countdown ticks every second, and otherwise only as
/// often as the item needs. A `TimelineView` in a menu bar label kept the
/// main thread busy updating the item from launch on, so the countdown ticks
/// on a timer instead.
@MainActor
@Observable
final class Countdown {
    private(set) var label = MenuBarLabel.idle(untracked: nil) {
        didSet {
            if label != oldValue {
                onLabelChange?(label)
            }
        }
    }

    /// What the panel shows, or `nil` when nothing runs or there is no store.
    private(set) var panel: CompactPanel?

    /// The break length the "Break for" list preselects: the last one used, in minutes.
    private(set) var breakMinutes: Int

    /// The workspaces to start or switch to, in their order. Empty without a store.
    ///
    /// Stored and renewed on every refresh, so the panel follows a new order
    /// or an archived workspace from Settings each time it opens.
    private(set) var workspaces: [Workspace] = []

    /// The presets a custom block can follow, in their order. Empty without a store.
    ///
    /// Names, not models: a preset can be removed in Settings while a closed
    /// panel still holds the form, and a removed model must not be read.
    private(set) var presets: [PresetName] = []

    /// Today's tracked time, such as `0:10`, or `nil` without a store.
    private(set) var trackedToday: String?

    /// Whether the panel is open. While it is, the countdown ticks every second.
    var isPanelOpen = false {
        didSet {
            if isPanelOpen != oldValue {
                reschedule()
            }
        }
    }

    /// Called with the new label each time it changes.
    @ObservationIgnored var onLabelChange: ((MenuBarLabel) -> Void)?

    /// The sounds and the notifications, or `nil` when the countdown is frozen.
    let alerts: AlertCenter?
    /// The question about time away, or `nil` without a store.
    let away: AwayQuestion?

    private let context: ModelContext?
    private let appStart: Date
    private let fixedTime: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var defaultsObserver: (any NSObjectProtocol)?
    /// What the last settle reported, and when. `nil` after a user's action,
    /// so only what runs out by itself plays a sound.
    @ObservationIgnored private var settled: Settled?
    /// The latest break with nothing running, still running or finished, or
    /// `nil`. A finished one keeps the end it really had, where untracked time
    /// starts. The views read it through ``panel`` and ``label``.
    @ObservationIgnored private var idleBreak: IdleBreak?
    /// Where the break with nothing running and the last break length are
    /// kept across launches, or `nil` to keep them in memory only.
    private let defaults: UserDefaults?
    /// Whether a refresh is under way. Saving to the defaults posts a change,
    /// which would otherwise refresh again inside it.
    @ObservationIgnored private var isRefreshing = false
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "countdown")

    /// A countdown over the store in `container`, or the outline dot alone
    /// when there is no store. With `fixedTime` it is computed for that
    /// instant, acts at that instant, never ticks and gives no alerts.
    ///
    /// `defaults` keeps the latest break with nothing running and the last
    /// break length across launches. Without it, as for the sample data, both
    /// stay in memory and start from `idleBreak` and the default length.
    ///
    /// The question about time away follows `awaySettings`, and notices time
    /// away through `idleTime` unless the countdown is frozen. `timeAway`
    /// waits from the start, as in a scenario.
    init(
        container: ModelContainer?,
        fixedTime: Date?,
        alerts: AlertCenter? = nil,
        defaults: UserDefaults? = nil,
        idleBreak: IdleBreak? = nil,
        awaySettings: AwaySettings = AwaySettings(defaults: nil),
        idleTime: (any IdleTimeReading)? = nil,
        timeAway: TimeAway? = nil,
    ) {
        context = container?.mainContext
        self.fixedTime = fixedTime
        let alerts = fixedTime == nil ? alerts : nil
        self.alerts = alerts
        self.defaults = defaults
        away = container.map {
            AwayQuestion(
                context: $0.mainContext, settings: awaySettings, alerts: alerts,
                idleTime: fixedTime == nil ? idleTime : nil, timeAway: timeAway,
            )
        }
        breakMinutes = TimerEngine.breakLength(remembered: defaults?.integer(forKey: Self.breakMinutesKey) ?? 0)
        if let defaults {
            self.idleBreak = Self.storedIdleBreak(in: defaults)
        } else {
            self.idleBreak = idleBreak
        }
        appStart = fixedTime ?? .now
        let next = refresh(at: appStart)
        guard fixedTime == nil, context != nil else { return }

        let timer = Timer(fire: next, interval: MenuBarLabel.untrackedThreshold, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                // The schedule runs on a clock that stops while the Mac sleeps,
                // so every tick sets the next one from the wall clock again.
                self?.reschedule()
            }
        }
        // Common modes, so it keeps ticking while a menu is open. The
        // countdown lives as long as the app, so the timer is never invalidated.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didWakeNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reschedule()
            }
        }
        // A switch changed in Settings replans the notifications at once.
        defaultsObserver = NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.reschedule()
            }
        }
    }

    /// The timer's state, `.idle` when nothing runs or there is no store.
    var state: TimerState {
        panel?.state ?? .idle
    }

    /// Whether a store is open. Without one there is nothing to start.
    var hasStore: Bool {
        context != nil
    }

    /// Takes `action` now, on the running block or the break with nothing running.
    /// Only +15 leaves the question about time away waiting.
    func perform(_ action: QuickAction) {
        act("take a quick action", keepsTimeAway: action == .extend) { engine, now in
            try changeBreak(with: engine, at: now) { try action.perform(with: engine, idleBreak: &$0, at: now) }
        }
    }

    /// Starts a break of `minutes` now, inside the running block or with
    /// nothing running, and remembers the length for next time.
    func startBreak(minutes: Int) {
        act("start a break") { engine, now in
            try changeBreak(with: engine, at: now) {
                try QuickAction.startBreak(minutes: minutes, with: engine, idleBreak: &$0, at: now)
            }
            // Only a break that started moves the preselection.
            breakMinutes = minutes
        }
        // Its end is announced too, so a first break asks as a first start does.
        alerts?.askPermissionIfUndetermined()
    }

    /// Takes the planned break that is due now, of `minutes`. It leaves the
    /// remembered length alone, because he did not choose this one.
    func startPlannedBreak(minutes: Int) {
        act("take a planned break") { try $0.startBreak(minutes: minutes, at: $1) }
        alerts?.askPermissionIfUndetermined()
    }

    /// Starts a block for `workspace` now at its default length and rhythm.
    /// Whatever runs ends first, so this also switches, and it ends a break
    /// with nothing running, silently.
    func start(_ workspace: Workspace) {
        startBlock { try $0.start(workspace, at: $1) }
    }

    /// Starts a block for `workspace` now, of `minutes`, following the preset
    /// with `presetID`, or with no rhythm when it is `nil`. Otherwise as ``start(_:)``.
    func start(_ workspace: Workspace, minutes: Int, presetID: FocusPreset.ID?) {
        guard let context else { return }
        startBlock { engine, now in
            let rhythm = try PresetRoster(context: context).rhythm(ofPreset: presetID)
            try engine.start(workspace, minutes: minutes, rhythm: rhythm, at: now)
        }
    }

    private func startBlock(_ body: (TimerEngine, Date) throws -> Void) {
        act("start a block", body)
        // The first start asks for the permission to notify, never the launch.
        alerts?.askPermissionIfUndetermined()
    }

    /// Ends the running block now.
    func endBlock() {
        act("end the block") { try $0.end(at: $1) }
    }

    /// Changes the entries as `answer` says about the time away that waits.
    func answer(_ answer: AwayAnswer) {
        guard let timeAway = away?.timeAway else { return }
        act("answer the question about time away") { try $0.settle(timeAway, as: answer, at: $1) }
    }

    /// Settles now, updates what the item and the panel show, and sets the next tick.
    func reschedule() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let next = refresh(at: fixedTime ?? .now)
        timer?.fireDate = next
    }

    /// Passes the break with nothing running at `now`, or `nil`, to `change`.
    /// One that stops running there is kept as finished.
    private func changeBreak(
        with engine: TimerEngine,
        at now: Date,
        _ change: (inout IdleBreak?) throws -> Void,
    ) throws {
        var running = try idleBreak?.running(beside: engine.settle(at: now), at: now)
        try change(&running)
        idleBreak = running ?? idleBreak?.ended(at: now)
    }

    /// Takes a step on the timer. Unless `keepsTimeAway`, one that succeeds
    /// drops the question about time away, which then counts as worked.
    private func act(_ what: String, keepsTimeAway: Bool = false, _ body: (TimerEngine, Date) throws -> Void) {
        guard let context else { return }
        do {
            try body(TimerEngine(context: context), fixedTime ?? .now)
            if !keepsTimeAway {
                away?.drop()
            }
        } catch {
            log.error("Could not \(what): \(error.localizedDescription)")
        }
        settled = nil
        reschedule()
    }

    /// Settles the timer at `now`, updates ``label`` and ``panel``, and returns when to refresh next.
    @discardableResult
    private func refresh(at now: Date) -> Date {
        guard let context else {
            label = .idle(untracked: nil)
            panel = nil
            workspaces = []
            presets = []
            trackedToday = nil
            return now.addingTimeInterval(MenuBarLabel.untrackedThreshold)
        }
        do {
            let engine = TimerEngine(context: context)
            let blockStatus = try engine.settle(at: now)
            // Before anything is shown, so a damaged break never is.
            let running = idleBreak?.running(beside: blockStatus, at: now)
            idleBreak = running ?? idleBreak?.ended(at: now)
            let status = running?.status(at: now) ?? blockStatus
            let since = try MenuBarLabel.untrackedStart(
                in: context, appStart: appStart, now: now, calendar: .current, idleBreak: idleBreak,
            )
            let block = try engine.runningBlock()
            let rhythm = try engine.rhythm(at: now)
            announce(status, rhythm: rhythm, workspace: block?.workspace?.name ?? "", at: now)
            away?.follow(status.state)
            label = MenuBarLabel(status: status, workspace: block?.workspace, untrackedSince: since, at: now)
            let tracked = try CompactPanel.trackedToday(in: context, now: now, calendar: .current)
            panel = running.map { CompactPanel(idleBreak: $0, at: now, tracked: tracked) }
                ?? CompactPanel(status: status, block: block, rhythm: rhythm, tracked: tracked)
            trackedToday = MenuBarLabel.hoursAndMinutes(tracked)
            workspaces = try WorkspaceRoster(context: context).activeWorkspaces()
            presets = try PresetRoster(context: context).presets().map(PresetName.init)
            saveBreaks()
            let next = MenuBarLabel.nextRedraw(status: status, rhythm: rhythm, untrackedSince: since, after: now)
            guard isPanelOpen, let tick = CompactPanel.nextRedraw(status: status, after: now) else { return next }
            return min(next, tick)
        } catch {
            log.error("The timer could not be read: \(error.localizedDescription)")
            settled = nil
            label = .idle(untracked: nil)
            panel = nil
            workspaces = []
            presets = []
            trackedToday = nil
            return now.addingTimeInterval(60)
        }
    }

    private struct Settled {
        let status: TimerStatus
        let rhythm: FocusRhythm?
        let time: Date
    }

    private static let breakMinutesKey = "break.lastMinutes"
    private static let idleBreakStartKey = "break.idle.start"
    private static let idleBreakEndKey = "break.idle.end"

    /// The latest break with nothing running kept in `defaults`, or `nil` when
    /// none is kept or what is kept is damaged.
    private static func storedIdleBreak(in defaults: UserDefaults) -> IdleBreak? {
        guard let start = defaults.object(forKey: idleBreakStartKey) as? Date,
              let end = defaults.object(forKey: idleBreakEndKey) as? Date
        else { return nil }
        return IdleBreak(start: start, end: end)
    }

    /// Keeps the latest break with nothing running and the last break length
    /// in the defaults, writing only what changed.
    private func saveBreaks() {
        guard let defaults else { return }
        if TimerEngine.breakLength(remembered: defaults.integer(forKey: Self.breakMinutesKey)) != breakMinutes {
            defaults.set(breakMinutes, forKey: Self.breakMinutesKey)
        }
        // Against the raw values, so a damaged pair is removed and a kept one is not written again.
        for (key, date) in [(Self.idleBreakStartKey, idleBreak?.start), (Self.idleBreakEndKey, idleBreak?.end)] {
            let stored = defaults.object(forKey: key)
            let isKept = date.map { stored as? Date == $0 } ?? (stored == nil)
            if !isKept {
                defaults.set(date, forKey: key)
            }
        }
    }

    /// Plays the sound of an alert whose moment passed since the last settle,
    /// and replans the pending notifications.
    private func announce(_ status: TimerStatus, rhythm: FocusRhythm?, workspace: String, at now: Date) {
        defer { settled = Settled(status: status, rhythm: rhythm, time: now) }
        guard let alerts else { return }
        if let settled, let kind = AlertKind.due(
            from: settled.status, rhythm: settled.rhythm, at: settled.time, to: status, at: now,
        ) {
            alerts.play(kind)
        }
        let plan = PlannedAlert.plan(
            for: status, rhythm: rhythm, workspace: workspace, settings: alerts.settings, at: now,
        )
        alerts.schedule(plan, at: now)
    }
}

/// A preset as a pop-up lists it.
struct PresetName: Identifiable, Equatable {
    let id: FocusPreset.ID
    /// The name shown: the preset's own, or "Unnamed" when it has none.
    let name: String

    init(_ preset: FocusPreset) {
        id = preset.id
        name = preset.name.isEmpty ? String(localized: "Unnamed") : preset.name
    }
}
