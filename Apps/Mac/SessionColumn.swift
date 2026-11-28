import DontBurnCore
import Foundation
import Observation
import os
import SwiftData

/// What the expanded panel's session column shows, renewed while it is shown.
///
/// It follows the events as they come, and once a second it looks again: a
/// turn that stopped becomes idle, an idle row's minutes count up, and a
/// session whose process is gone leaves. The sessions' projects are looked up
/// when it is shown and with each event only, and the terminals' permissions
/// when it is shown. Nothing runs while it is not shown.
///
/// Focus brings a row's tab forward. When the tab is gone, the row says so for
/// ``goneNoteLength``, then leaves. When the terminal does not answer, the row
/// says so until the column is shown again.
@MainActor
@Observable
final class SessionColumn {
    /// The sessions, as of the last look.
    private(set) var list = SessionList(sessions: [], at: .distantPast) { _ in nil }

    /// Why the list is empty, as of the moment the column was shown. A
    /// session that has shown since proves that a hook is there.
    private(set) var noSessions = NoSessions.noneRunning

    /// What the last Focus came to, by session, for a row that says it.
    private(set) var notes: [AgentSession.ID: FocusOutcome] = [:]
    /// The session whose Focus runs, if any. One at a time.
    private(set) var focusing: AgentSession.ID?
    /// Called after Focus brought a tab forward.
    @ObservationIgnored var onFocused: (() -> Void)?

    /// How long a row whose tab is gone says so before it leaves.
    static let goneNoteLength: TimeInterval = 3

    /// Whether the panel shows the column: it is open and expanded.
    var isShown = false {
        didSet {
            if isShown != oldValue {
                shownChanged()
            }
        }
    }

    private let monitor: SessionMonitor?
    private let terminalFocus: TerminalFocus
    private let projects: ModelContext?
    private let folders: ModelContext?
    private let fixedTime: Date?
    /// Reads the hook of each profile.
    private let readHooks: () -> [HookStatus]
    /// The projects as of the last lookup, by session id.
    @ObservationIgnored private var sessionProjects: [AgentSession.ID: Project] = [:]
    @ObservationIgnored private var timer: Timer?
    /// When each row whose tab is gone leaves.
    @ObservationIgnored private var leaving: [AgentSession.ID: Date] = [:]
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "sessions")

    /// The sessions of `monitor`, or none without it, with their projects from
    /// `container` and the folders in `localContainer`. Without either store
    /// every session is listed under Other.
    ///
    /// `readHooks` runs only when the column is shown and there is no session,
    /// once each time. With `fixedTime` the list is the one of that instant.
    /// `focus` brings the rows' tabs forward.
    init(
        monitor: SessionMonitor?,
        focus: TerminalFocus,
        container: ModelContainer?,
        localContainer: ModelContainer?,
        fixedTime: Date?,
        readHooks: @escaping () -> [HookStatus],
    ) {
        self.monitor = monitor
        terminalFocus = focus
        projects = container?.mainContext
        folders = localContainer?.mainContext
        self.fixedTime = fixedTime
        self.readHooks = readHooks
        monitor?.onEvent = { [weak self] in
            if self?.isShown == true {
                self?.lookUpProjects()
                self?.look()
            }
        }
    }

    /// Shows the sessions under `filter`.
    func show(_ filter: SessionFilter) {
        look(filter: filter)
    }

    /// Brings the tab of the session `id` forward. Ignored while another Focus runs.
    func focus(_ id: AgentSession.ID) {
        guard focusing == nil, let session = monitor?.currentSessions().first(where: { $0.id == id }) else { return }
        focusing = id
        notes[id] = nil
        // The button cannot wait: a focus takes about 0.3 s, longer for a
        // minimized window, and as long as the user takes over macOS's prompt.
        Task { [self] in
            let outcome = await terminalFocus.focus(session)
            focusing = nil
            focused(id, outcome)
        }
    }

    private func focused(_ id: AgentSession.ID, _ outcome: FocusOutcome) {
        switch outcome {
        case .focused:
            onFocused?()
        case .gone where !isShown:
            monitor?.forget(id)
        case .gone:
            notes[id] = outcome
            leaving[id] = (fixedTime ?? .now).addingTimeInterval(Self.goneNoteLength)
        case .timedOut, .failed:
            if isShown {
                notes[id] = outcome
            }
        case .denied, .notSent:
            break
        }
        // A denied terminal's rows lose their Focus button.
        look()
    }

    private func shownChanged() {
        timer?.invalidate()
        timer = nil
        guard isShown else {
            // A row whose tab is gone leaves at once, and no note waits for the next time.
            for id in leaving.keys {
                monitor?.forget(id)
            }
            leaving = [:]
            notes = [:]
            return
        }
        lookUpProjects()
        look()
        if list.isEmpty {
            noSessions = NoSessions(hooks: readHooks())
        }
        // Read off the main actor, so the panel does not wait for it. A
        // denied terminal's buttons go when the answer comes.
        Task { [self] in
            await terminalFocus.readPermissions()
            look()
        }
        guard fixedTime == nil else { return }
        let timer = Timer(timeInterval: 1, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.look() }
        }
        // Common modes, so it keeps looking while a menu is open.
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    private func look(filter: SessionFilter? = nil) {
        let now = fixedTime ?? .now
        for (id, time) in leaving where time <= now {
            monitor?.forget(id)
            leaving[id] = nil
            notes[id] = nil
        }
        let new = SessionList(
            sessions: monitor?.currentSessions() ?? [], filter: filter ?? list.filter,
            automationDenied: terminalFocus.denied, at: now,
        ) { sessionProjects[$0.id] }
        if new != list {
            list = new
        }
        if !new.isEmpty {
            noSessions = .noneRunning
        }
    }

    /// Finds each session's project in the stores. When they cannot be read,
    /// every session is listed under Other until the next lookup.
    private func lookUpProjects() {
        guard let projects, let folders else { return }
        var found: [AgentSession.ID: Project] = [:]
        do {
            let all = try projects.fetch(FetchDescriptor<Project>())
            let holders = ProjectFolders(context: folders)
            for session in monitor?.currentSessions() ?? [] {
                found[session.id] = try session.project(in: holders, among: all)
            }
        } catch {
            found = [:]
            // The error may name a path, so only its code is logged.
            log.error("The sessions' projects could not be read, error \((error as NSError).code)")
        }
        sessionProjects = found
    }
}
