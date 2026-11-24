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
    /// The sessions as their events left them.
    private(set) var store: SessionStore

    /// The folder of ``SessionStore/fileName``, or `nil` to keep the sessions
    /// in memory only, as with the sample data.
    private let directory: URL?
    private let receiver: any HookMessageReceiving
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "sessions")

    /// Loads the sessions saved in `directory`, if any, and drops those whose
    /// `claude` process is gone. Receives nothing until ``start()``.
    init(directory: URL?, receiver: any HookMessageReceiving) {
        self.directory = directory
        self.receiver = receiver
        var store = directory.map(SessionStore.load(in:)) ?? SessionStore()
        store.prune(keepingAlive: Self.isAlive)
        self.store = store
    }

    /// Opens the channel, and closes and removes it when the app quits.
    func start() {
        do {
            try receiver.start { [weak self] message, arrival in self?.receive(message, at: arrival) }
        } catch {
            log.error("The hook channel could not be opened: \(String(describing: error), privacy: .public)")
            return
        }
        NotificationCenter.default.addObserver(
            forName: NSApplication.willTerminateNotification, object: nil, queue: .main,
        ) { [weak self] _ in
            MainActor.assumeIsolated { self?.receiver.stop() }
        }
    }

    private func receive(_ message: Data, at arrival: Date) {
        let event: HookEvent
        do {
            event = try store.receive(message, at: arrival)
        } catch {
            log.error("Refused a hook message: \(String(describing: error), privacy: .public)")
            return
        }
        log.info("Received \(event.name, privacy: .public)")
        store.prune(keepingAlive: Self.isAlive)
        guard let directory else { return }
        do {
            try store.save(in: directory)
        } catch {
            // The error's description holds the path, so only its code is logged.
            log.error("The sessions could not be saved, error \((error as NSError).code)")
        }
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
