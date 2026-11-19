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
/// settled state. Beside the engine it keeps the break with nothing running
/// (``IdleBreak``) and the last break length, which no store holds. While
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

    private let context: ModelContext?
    private let appStart: Date
    private let fixedTime: Date?
    @ObservationIgnored private var timer: Timer?
    @ObservationIgnored private var wakeObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var defaultsObserver: (any NSObjectProtocol)?
    /// The status the last settle reported, and when. `nil` after a user's
    /// action, so only a block or a break that runs out by itself plays a sound.
    @ObservationIgnored private var settled: (status: TimerStatus, at: Date)?
    /// The break with nothing running, or `nil`. The views read it through ``panel`` and ``label``.
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
    /// `defaults` keeps the break with nothing running and the last break
    /// length across launches. Without it, as for the sample data, both stay
    /// in memory and start from `idleBreak` and the default length.
    init(
        container: ModelContainer?,
        fixedTime: Date?,
        alerts: AlertCenter? = nil,
        defaults: UserDefaults? = nil,
        idleBreak: IdleBreak? = nil,
    ) {
        context = container?.mainContext
        self.fixedTime = fixedTime
        self.alerts = fixedTime == nil ? alerts : nil
        self.defaults = defaults
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
    func perform(_ action: QuickAction) {
        act("take a quick action") { try action.perform(with: $0, idleBreak: &idleBreak, at: $1) }
    }

    /// Starts a break of `minutes` now, inside the running block or with
    /// nothing running, and remembers the length for next time.
    func startBreak(minutes: Int) {
        breakMinutes = minutes
        act("start a break") {
            try QuickAction.startBreak(minutes: minutes, with: $0, idleBreak: &idleBreak, at: $1)
        }
        // Its end is announced too, so a first break asks as a first start does.
        alerts?.askPermissionIfUndetermined()
    }

    /// Starts a block for `workspace` now, of `minutes` or its default length.
    /// Whatever runs ends first, so this also switches, and it ends a break
    /// with nothing running, silently.
    func start(_ workspace: Workspace, minutes: Int? = nil) {
        act("start a block") { try $0.start(workspace, minutes: minutes, at: $1) }
        // The first start asks for the permission to notify, never the launch.
        alerts?.askPermissionIfUndetermined()
    }

    /// Ends the running block now.
    func endBlock() {
        act("end the block") { try $0.end(at: $1) }
    }

    /// Settles now, updates what the item and the panel show, and sets the next tick.
    func reschedule() {
        guard !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        let next = refresh(at: fixedTime ?? .now)
        timer?.fireDate = next
    }

    private func act(_ what: String, _ body: (TimerEngine, Date) throws -> Void) {
        guard let context else { return }
        do {
            try body(TimerEngine(context: context), fixedTime ?? .now)
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
            trackedToday = nil
            return now.addingTimeInterval(MenuBarLabel.untrackedThreshold)
        }
        do {
            let engine = TimerEngine(context: context)
            let blockStatus = try engine.settle(at: now)
            idleBreak = idleBreak?.running(beside: blockStatus, at: now)
            let status = idleBreak?.status(at: now) ?? blockStatus
            let since = try MenuBarLabel.untrackedStart(
                in: context, appStart: appStart, now: now, calendar: .current,
            )
            let block = try engine.runningBlock()
            announce(status, workspace: block?.workspace?.name ?? "", at: now)
            label = MenuBarLabel(status: status, workspace: block?.workspace, untrackedSince: since, at: now)
            let tracked = try CompactPanel.trackedToday(in: context, now: now, calendar: .current)
            panel = idleBreak.map { CompactPanel(idleBreak: $0, at: now, tracked: tracked) }
                ?? CompactPanel(status: status, block: block, tracked: tracked)
            trackedToday = MenuBarLabel.hoursAndMinutes(tracked)
            workspaces = try WorkspaceRoster(context: context).activeWorkspaces()
            saveBreaks()
            let next = MenuBarLabel.nextRedraw(status: status, untrackedSince: since, after: now)
            guard isPanelOpen, let tick = CompactPanel.nextRedraw(status: status, after: now) else { return next }
            return min(next, tick)
        } catch {
            log.error("The timer could not be read: \(error.localizedDescription)")
            settled = nil
            label = .idle(untracked: nil)
            panel = nil
            workspaces = []
            trackedToday = nil
            return now.addingTimeInterval(60)
        }
    }

    private static let breakMinutesKey = "break.lastMinutes"
    private static let idleBreakStartKey = "break.idle.start"
    private static let idleBreakEndKey = "break.idle.end"

    /// The break with nothing running kept in `defaults`, or `nil` when none
    /// is kept or what is kept is damaged.
    private static func storedIdleBreak(in defaults: UserDefaults) -> IdleBreak? {
        guard let start = defaults.object(forKey: idleBreakStartKey) as? Date,
              let end = defaults.object(forKey: idleBreakEndKey) as? Date
        else { return nil }
        return IdleBreak(start: start, end: end)
    }

    /// Keeps the break with nothing running and the last break length in the
    /// defaults, writing only what changed.
    private func saveBreaks() {
        guard let defaults else { return }
        if TimerEngine.breakLength(remembered: defaults.integer(forKey: Self.breakMinutesKey)) != breakMinutes {
            defaults.set(breakMinutes, forKey: Self.breakMinutesKey)
        }
        guard Self.storedIdleBreak(in: defaults) != idleBreak else { return }
        if let idleBreak {
            defaults.set(idleBreak.start, forKey: Self.idleBreakStartKey)
            defaults.set(idleBreak.end, forKey: Self.idleBreakEndKey)
        } else {
            defaults.removeObject(forKey: Self.idleBreakStartKey)
            defaults.removeObject(forKey: Self.idleBreakEndKey)
        }
    }

    /// Plays the sound of an alert whose moment passed since the last settle,
    /// and replans the pending notifications.
    private func announce(_ status: TimerStatus, workspace: String, at now: Date) {
        defer { settled = (status, now) }
        guard let alerts else { return }
        if let settled, let kind = AlertKind.due(from: settled.status, at: settled.at, to: status, at: now) {
            alerts.play(kind)
        }
        alerts.schedule(PlannedAlert.plan(for: status, workspace: workspace, settings: alerts.settings, at: now))
    }
}
