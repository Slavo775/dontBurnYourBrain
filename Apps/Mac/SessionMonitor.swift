import AppKit
import DontBurnCore
import os

/// The agent sessions on this Mac, kept up to date from the hook tool's events.
///
/// Without the hook installed no event comes, so the store stays empty and
/// nothing else changes. A channel that cannot be opened is logged, and the
/// app runs on without sessions.
@MainActor
final class SessionMonitor {
    /// The events the hook is installed for, the only names the log shows.
    private static let knownEventNames = Set(HookEvent.handledNames)

    /// Called after each event that was received.
    var onEvent: (() -> Void)?

    /// The sessions as their events left them.
    private var store: SessionStore

    /// The folder of ``SessionStore/fileName``, or `nil` to keep the sessions
    /// in memory only, as with the sample data.
    private let directory: URL?
    /// The channel, or `nil` for none, as with the sample data.
    private let receiver: (any HookMessageReceiving)?
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "sessions")

    /// Loads the sessions saved in `directory`, if any, and drops those whose
    /// `claude` process is gone. Receives nothing until ``start()``.
    init(directory: URL, receiver: any HookMessageReceiving) {
        self.directory = directory
        self.receiver = receiver
        store = SessionStore.load(in: directory)
        prune()
    }

    /// The sample sessions in `sample`, in memory, with no channel, so no real
    /// session ever joins them.
    init(sample: SessionStore) {
        directory = nil
        receiver = nil
        store = sample
    }

    /// Opens the channel, and closes and removes it when the app quits.
    func start() {
        guard let receiver else { return }
        do {
            try receiver.start { [weak self] message, arrival in self?.receive(message, at: arrival) }
        } catch {
            log.error("The hook channel could not be opened: \(String(describing: error), privacy: .public)")
            // Without events the saved sessions would keep their last state for ever. The file stays.
            store = SessionStore()
            return
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.receiver?.stop() }
        }
    }

    /// The sessions that are there now, oldest first, without those that
    /// ended and those whose `claude` process is gone.
    func currentSessions() -> [AgentSession] {
        prune()
        return store.sessions
    }

    private func receive(_ message: Data, at arrival: Date) {
        let event: HookEvent
        do {
            event = try store.receive(message, at: arrival)
        } catch {
            log.error("Refused a hook message: \(String(describing: error), privacy: .public)")
            return
        }
        // The name comes from outside the app, so only one of Claude Code's own goes to the log as it is.
        let name = Self.knownEventNames.contains(event.name) ? event.name : "an unknown event"
        log.info("Received \(name, privacy: .public)")
        prune()
        defer { onEvent?() }
        guard let directory else { return }
        do {
            try store.save(in: directory)
        } catch {
            // The error's description holds the path, so only its code is logged.
            log.error("The sessions could not be saved, error \((error as NSError).code)")
        }
    }

    private func prune() {
        // The sample sessions have no process to ask about.
        guard receiver != nil else { return }
        store.prune(keepingAlive: Self.isAlive)
    }

    /// Whether the session's `claude` process still runs.
    ///
    /// ponytail: a process ID the system has given to a new process since
    /// counts as alive, until that one ends too. Compare the process's start
    /// time from `sysctl` with the session's first event when that matters.
    private static func isAlive(_ session: AgentSession) -> Bool {
        // A signal of 0 only asks whether the process exists. EPERM: it does, under another user.
        session.processID > 0 && (kill(session.processID, 0) == 0 || errno == EPERM)
    }
}
