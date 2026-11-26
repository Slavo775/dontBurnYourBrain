import AppKit
import CoreGraphics
import DontBurnCore
import Observation

/// Reads how long the Mac has had no input. It says nothing about what the input was.
@MainActor
protocol IdleTimeReading {
    /// The seconds since the last key press, click or other input of this login session.
    func secondsSinceLastInput() -> TimeInterval
}

/// The system's time since the last input. It needs no permission, and no
/// Input Monitoring prompt comes, because no event is read.
struct SystemIdleTime: IdleTimeReading {
    func secondsSinceLastInput() -> TimeInterval {
        // ~0 is `kCGAnyInputEventType`: every kind of input.
        guard let anyInput = CGEventType(rawValue: ~0) else { return 0 }
        return CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: anyInput)
    }
}

/// The Dev build's stand-in: input comes once every `cycle` seconds from
/// `launch` on, so each cycle is a time away. See ``AwayStandIn``.
struct SimulatedIdleTime: IdleTimeReading {
    let launch: Date
    let cycle: Int

    func secondsSinceLastInput() -> TimeInterval {
        AwayStandIn.secondsSinceLastInput(at: .now, launch: launch, cycle: cycle)
    }
}

/// Notices the return to the Mac after a time without input or after sleep,
/// and reports it with the last input before it.
///
/// While ``isWatching``, it reads the idle time when it could first reach the
/// threshold, so about once per threshold while he works. Once the threshold
/// is reached, it reads every second until the return, also after watching
/// stops, such as when the block runs out meanwhile, so the return is found
/// within a second. A sleep that begins while ``isBlockRunning``, working, on
/// a break or paused, or during a time away, counts as time away from the
/// last input before it, and waking is the return. One that begins with no
/// block running, such as after the block ran out or on a break with nothing
/// running, counts as nothing. Whether a work entry ran during the time away,
/// and from when, is for the caller to decide.
@MainActor
final class AwayWatcher {
    /// Whether he works now, so a time away is worth noticing.
    var isWatching = false {
        didSet {
            if isWatching != oldValue {
                // From the run loop, so a report never runs inside the caller's own update.
                schedule(in: 0)
            }
        }
    }

    /// Whether a block runs now, working, on a break or paused, so a sleep that
    /// begins now counts as time away. A break may run out during the sleep,
    /// and work go on.
    var isBlockRunning = false

    /// How many seconds without input count as away. A change reads the idle
    /// time again at once while watching, so a shorter threshold never waits
    /// for the read the longer one planned.
    var threshold: TimeInterval {
        didSet {
            if threshold != oldValue, isWatching, awayStart == nil {
                schedule(in: 0)
            }
        }
    }

    /// Called with the last input before the time away and the return.
    var onReturn: ((_ lastInput: Date, _ returned: Date) -> Void)?

    private let idleTime: any IdleTimeReading
    /// The last input before the time away under way, or `nil` while he is here.
    private var awayStart: Date?
    private var timer: Timer?
    private var observers: [any NSObjectProtocol] = []

    /// A watcher reading `idleTime`, which counts as away from `threshold` seconds on.
    init(idleTime: any IdleTimeReading, threshold: TimeInterval) {
        self.idleTime = idleTime
        self.threshold = threshold
        let center = NSWorkspace.shared.notificationCenter
        observers = [
            center.addObserver(forName: NSWorkspace.willSleepNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.macWillSleep() }
            },
            center.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.macDidWake() }
            },
        ]
    }

    private func macWillSleep() {
        if isBlockRunning, awayStart == nil {
            awayStart = Date.now.addingTimeInterval(-idleTime.secondsSinceLastInput())
        }
    }

    private func macDidWake() {
        if let awayStart {
            self.awayStart = nil
            onReturn?(awayStart, .now)
        }
        schedule(in: 0)
    }

    private func check() {
        let idle = idleTime.secondsSinceLastInput()
        let lastInput = Date.now.addingTimeInterval(-idle)
        if let awayStart {
            // A second of slack, since two readings of the same input differ by a little.
            if lastInput > awayStart.addingTimeInterval(1) {
                self.awayStart = nil
                onReturn?(awayStart, lastInput)
            }
        } else if isWatching, idle >= threshold {
            awayStart = lastInput
        }
        if awayStart != nil {
            schedule(in: 1)
        } else if isWatching {
            schedule(in: max(1, threshold - idle))
        } else {
            timer?.invalidate()
            timer = nil
        }
    }

    private func schedule(in seconds: TimeInterval) {
        timer?.invalidate()
        let timer = Timer(timeInterval: seconds, repeats: false) { [weak self] _ in
            MainActor.assumeIsolated { self?.check() }
        }
        // Common modes, so it keeps reading while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }
}

/// The question about time away, from Settings, General: whether it is asked,
/// and after how many minutes without input.
///
/// Kept in the app's own defaults, as `away.ask` and `away.thresholdMinutes`,
/// or in memory only without them, as for the sample data.
@MainActor
@Observable
final class AwaySettings {
    static let asksKey = "away.ask"
    static let thresholdKey = "away.thresholdMinutes"

    /// Whether the app asks about time away. With it off, time away counts as worked.
    var asks: Bool {
        didSet { defaults?.set(asks, forKey: Self.asksKey) }
    }

    /// How long without input before it asks, in minutes, within ``TimeAway/thresholdRange``.
    var thresholdMinutes: Int {
        didSet { defaults?.set(thresholdMinutes, forKey: Self.thresholdKey) }
    }

    /// ``thresholdMinutes`` in seconds.
    var threshold: TimeInterval {
        TimeInterval(thresholdMinutes) * 60
    }

    @ObservationIgnored private let defaults: UserDefaults?

    /// The settings kept in `defaults`, or in memory when it is `nil`.
    /// `thresholdMinutes`, from the Dev build's launch argument, replaces the
    /// stored threshold for this launch without being stored.
    init(defaults: UserDefaults?, thresholdMinutes: Int? = nil) {
        self.defaults = defaults
        asks = defaults?.object(forKey: Self.asksKey) as? Bool ?? true
        self.thresholdMinutes = thresholdMinutes
            ?? TimeAway.thresholdMinutes(remembered: defaults?.integer(forKey: Self.thresholdKey) ?? 0)
    }
}
