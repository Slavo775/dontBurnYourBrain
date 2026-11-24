import Foundation

// Sessions belong to this Mac and change by the second, so they live in a
// small JSON file next to the local store, never in a synced store. A file
// that cannot be read loses nothing that matters: each session comes back
// with its next hook event.

/// The agent tool a session runs in.
public enum AgentTool: String, Codable, Sendable {
    /// Claude Code.
    case claude
}

/// What an agent session is doing.
public enum AgentSessionState: String, Codable, Sendable {
    /// Started, and no turn has run yet.
    case registered
    /// A turn runs, or the main thread stopped while background work it waits for runs.
    case working
    /// A permission prompt waits for the user.
    case waitingForYou
    /// The last turn ended.
    case finished
    /// The session ended. ``SessionStore/prune(keepingAlive:)`` drops it.
    case gone

    /// The group of the session list that shows this state, or `nil` for
    /// ``gone``, which no group shows.
    public var group: SessionGroup? {
        switch self {
        case .waitingForYou: .needsYou
        case .working: .working
        case .registered, .finished: .idle
        case .gone: nil
        }
    }
}

/// A group of the session list.
public enum SessionGroup: Sendable {
    /// Sessions waiting for the user.
    case needsYou
    /// Sessions at work.
    case working
    /// Sessions with nothing to do.
    case idle
}

/// One agent session on this Mac, as its hook events describe it.
///
/// Its folder, profile, terminal and tab come from the first event of its
/// `claude` process, and are taken again when an event comes from another
/// process, as after a resume. So a session that changes its working folder
/// keeps the one it started in.
public struct AgentSession: Codable, Equatable, Identifiable, Sendable {
    /// The name of the default profile's folder, `~/.claude`.
    public static let defaultProfileName = ".claude"

    /// The tool the session runs in.
    public private(set) var tool = AgentTool.claude
    /// The session id.
    public let id: String
    /// The profile folder, or `nil` when the event named none. The default
    /// profile normally comes as its path, `~/.claude`, since every event
    /// carries `transcript_path`. See ``HookEvent/profile``.
    public private(set) var profile: String?
    /// The working folder the session started in, as the hook sent it. Empty when it sent none.
    public private(set) var folder = ""
    /// The bundle identifier of the terminal app, or `nil` when the hook ran outside one it knows.
    public private(set) var terminalBundleIdentifier: String?
    /// The ID of the `claude` process. Together with ``tty`` and ``id`` it
    /// names the tab, since a tty is given to a new tab as soon as its tab closes.
    public private(set) var processID: Int32 = 0
    /// The tty of the `claude` process, such as `ttys004`. Terminal's handle for the tab.
    public private(set) var tty: String?
    /// iTerm2's identifier for the tab: the UUID after the colon in
    /// `ITERM_SESSION_ID`, set whenever the environment held a valid one,
    /// whatever the terminal. The variable is inherited, by tmux for one, so
    /// only the iTerm2 adapter reads it.
    public private(set) var tabID: String?
    /// When the last event that showed activity came. A `Notification` with
    /// `idle_prompt` reports the lack of it, so it does not count.
    public private(set) var lastActivity: Date
    /// The state the last event set, before ``finishDelay`` is applied.
    fileprivate var state = AgentSessionState.registered
    /// Until when a turn that stopped still reads as working.
    fileprivate var workingUntil: Date?

    /// How long a stopped turn still reads as working, so two subagents that
    /// finish close together do not make the state flicker.
    ///
    /// The spike saw the next turn start "two seconds later", in a log that
    /// counts whole seconds, so the real gap may be anything below three.
    public static let finishDelay: TimeInterval = 3

    /// The state at `now`: ``AgentSessionState/working`` for ``finishDelay``
    /// after a `Stop`, then the state the events set.
    public func state(at now: Date) -> AgentSessionState {
        if let workingUntil, now < workingUntil {
            return .working
        }
        return state
    }

    /// The name the profile is shown by: its folder's name.
    public var profileName: String {
        profile.map { ($0 as NSString).lastPathComponent } ?? Self.defaultProfileName
    }

    /// The name the session is shown by: its folder's name.
    public var folderName: String {
        (folder as NSString).lastPathComponent
    }

    /// The project whose folder holds the session's folder, or `nil` when
    /// none does, which lists the session under "Other".
    ///
    /// Worked out each time, so a folder given to a project or taken from it
    /// counts at once. An empty or relative folder has no project.
    public func project(in folders: ProjectFolders, among projects: [Project]) throws -> Project? {
        try folders.project(holding: folder, among: projects)
    }

    fileprivate init(id: String, event: HookEvent, processID: Int32, at now: Date) {
        self.id = id
        lastActivity = now
        takeDetails(of: event, processID: processID)
    }

    fileprivate mutating func takeDetails(of event: HookEvent, processID: Int32) {
        self.processID = processID
        profile = event.profile
        folder = event.folder ?? ""
        terminalBundleIdentifier = event.environment?.bundleIdentifier
        tty = event.tty
        let afterColon = event.environment?.iTermSessionID?.split(separator: ":", maxSplits: 1).dropFirst().first
        tabID = afterColon.map(String.init).flatMap { UUID(uuidString: $0) == nil ? nil : $0 }
    }

    fileprivate mutating func apply(_ effect: Effect, at now: Date) {
        switch effect {
        case .idle:
            // ponytail: the only end of a turn that sent no Stop. After a
            // denied permission it comes about a minute later. After an Esc
            // none came within two minutes in the spike, so such a session
            // stays working until its next event.
            if state == .working || state == .waitingForYou {
                state = .finished
                workingUntil = nil
            }
            return
        case .register: set(.registered)
        case .activity: break
        case .work: set(.working)
        case .wait: set(.waitingForYou)
        case .stop(stillWorking: true): set(.working)
        case .stop(stillWorking: false):
            set(.finished)
            workingUntil = now.addingTimeInterval(Self.finishDelay)
        case .end: set(.gone)
        }
        lastActivity = now
    }

    private mutating func set(_ state: AgentSessionState) {
        self.state = state
        workingUntil = nil
    }
}

/// What one hook event does to its session.
private enum Effect: Equatable {
    /// The background work that keeps a session working after a `Stop`,
    /// as the owner decided. A background `shell` does not.
    static let workThatKeepsWorking: Set = ["subagent", "workflow", "teammate"]
    /// The notifications the app uses. Every other kind, `auth_success` among them, is ignored.
    static let notifications: [String: Effect] = ["permission_prompt": .wait, "idle_prompt": .idle]

    case register, activity, work, wait, stop(stillWorking: Bool), idle, end

    /// The effect of `event`, or `nil` when the app ignores it.
    init?(_ event: HookEvent) {
        switch event.name {
        // Compacting can happen in the middle of a turn, so it changes no state.
        case "SessionStart": self = event.source == "compact" ? .activity : .register
        case "UserPromptSubmit": self = .work
        case "PermissionRequest": self = .wait
        case "Notification":
            guard let effect = Self.notifications[event.notificationType ?? ""] else { return nil }
            self = effect
        case "Stop", "StopFailure":
            let tasks = event.backgroundTasks ?? []
            self = .stop(stillWorking: tasks.contains { Self.workThatKeepsWorking.contains($0.type ?? "") })
        // An empty agent type is the agent Claude Code runs for itself after a Stop.
        case "SubagentStart", "SubagentStop":
            guard event.agentType?.isEmpty == false else { return nil }
            self = .activity
        case "SessionEnd": self = .end
        default: return nil
        }
    }
}

/// The agent sessions on this Mac, kept up to date from hook events.
///
/// Pure: the time of each event and the check whether a session's process
/// still runs are passed in, and nothing is scheduled or read from the clock.
/// A session the store has not seen is added by its first event, whatever
/// the event, except a `SessionEnd`. Events the app does not use, events
/// without the `claude` process ID, and a `SessionEnd` from another process
/// than the session's change nothing.
public struct SessionStore: Codable, Equatable, Sendable {
    /// The file's name, next to ``ModelStore/localFileName`` in the same folder.
    public static let fileName = "Sessions.json"
    /// The largest file ``load(in:)`` reads, in bytes.
    public static let maximumFileSize = 1024 * 1024

    /// The sessions, oldest first.
    public private(set) var sessions: [AgentSession] = []

    /// A store with no sessions.
    public init() {}

    /// Applies `event`, which the app received at `now`.
    public mutating func apply(_ event: HookEvent, at now: Date) {
        guard let processID = event.processID, let effect = Effect(event) else { return }
        guard let index = sessions.firstIndex(where: { $0.id == event.sessionID }) else {
            guard effect != .end else { return }
            var session = AgentSession(id: event.sessionID, event: event, processID: processID, at: now)
            session.apply(effect, at: now)
            sessions.append(session)
            return
        }
        if sessions[index].processID != processID {
            // A resumed session can be open in two tabs at once. The older
            // tab's end must not take the live one with it.
            guard effect != .end else { return }
            sessions[index].takeDetails(of: event, processID: processID)
        }
        sessions[index].apply(effect, at: now)
    }

    /// Applies the hook tool's `message`, which the app received at `now`,
    /// once ``HookEvent/decode(_:)`` accepts it, and returns its event.
    ///
    /// A message that is too large or has the wrong shape changes nothing,
    /// and the ``HookEventError`` is thrown.
    @discardableResult
    public mutating func receive(_ message: Data, at now: Date) throws -> HookEvent {
        let event = try HookEvent.decode(message)
        apply(event, at: now)
        return event
    }

    /// Drops every session that ended, and every one whose `claude` process
    /// is gone, as `isAlive` tells.
    ///
    /// Call it whenever the sessions are looked at, and after ``load(in:)``.
    /// `isAlive` comes from the app, which checks the process and guards
    /// against a process ID given to another process.
    public mutating func prune(keepingAlive isAlive: (AgentSession) -> Bool) {
        sessions.removeAll { $0.state == .gone || !isAlive($0) }
    }

    /// The sessions saved in ``fileName`` inside `directory`, or none when
    /// the file is missing, larger than ``maximumFileSize`` or cannot be decoded.
    ///
    /// Fields the file holds beyond the session's own are dropped.
    public static func load(in directory: URL) -> SessionStore {
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        // A missing or unreadable file only loses sessions that come back with their next event.
        guard let handle = try? FileHandle(forReadingFrom: url) else { return SessionStore() }
        // Closing a file that was only read can lose nothing.
        defer { try? handle.close() }
        // Reading one byte past the limit tells a file that is too large without reading all of it.
        guard let data = try? handle.read(upToCount: maximumFileSize + 1),
              data.count <= maximumFileSize,
              let store = try? JSONDecoder().decode(SessionStore.self, from: data)
        else { return SessionStore() }
        return store
    }

    /// Writes the sessions to ``fileName`` inside `directory`, at once or not
    /// at all. Creates `directory` when it is missing.
    public func save(in directory: URL) throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: Self.fileName, directoryHint: .notDirectory)
        try JSONEncoder().encode(self).write(to: url, options: .atomic)
    }
}
