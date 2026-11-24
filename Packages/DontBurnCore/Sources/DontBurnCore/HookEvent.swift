import Foundation

/// Why a hook event was refused.
public enum HookEventError: Error, Equatable, Sendable {
    /// The event is larger than ``HookEvent/maximumSize``.
    case tooLarge
    /// The event is not a JSON object of the expected shape, or lacks its
    /// name or session id, or names a process ID below 1, or, in the hook
    /// tool, comes without a valid `CLAUDE_PID`.
    case malformed
}

/// One Claude Code hook event, cut down to the fields the app may keep.
///
/// The event fields keep Claude Code's own names, so the hook tool can decode
/// Claude Code's event into this type, which drops every other field, such as
/// the prompt, the tool input and the messages. The tool then adds what it
/// reads from its environment and its parent process, and sends the result to
/// the app, which reads it with ``decode(_:)``. See "The event format and the
/// fields the app uses" in `docs/spikes/claude-hook.md`.
public struct HookEvent: Codable, Equatable, Sendable {
    /// The largest event ``decode(_:)`` accepts, in bytes. A trimmed event
    /// takes a few hundred.
    public static let maximumSize = 64 * 1024

    /// The largest event from Claude Code that ``init(claudeEvent:environment:tty:)``
    /// takes, in bytes.
    ///
    /// Far above ``maximumSize``, because Claude Code's event carries the
    /// prompt and the tool's input: a `PermissionRequest` to write a large file
    /// can take megabytes. Only the trimmed event has to fit ``maximumSize``.
    public static let maximumClaudeEventSize = 16 * 1024 * 1024

    /// The events ``SessionStore`` acts on, so the hook is installed for
    /// exactly these, in this order. A name added to the store's rules goes here too.
    public static let handledNames = [
        "SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "Stop",
        "StopFailure", "SubagentStart", "SubagentStop", "SessionEnd",
    ]

    /// The event's name, such as `Stop`, from `hook_event_name`.
    public var name: String
    /// The session's identifier, from `session_id`.
    public var sessionID: String
    /// The session's working folder, from `cwd`.
    public var folder: String?
    /// The path of the session's transcript, from `transcript_path`. The app
    /// keeps nothing of it but the profile folder, and never reads the file.
    public var transcriptPath: String?
    /// How a `SessionStart` came about: `startup`, `resume`, `clear`,
    /// `compact` or `fork`.
    public var source: String?
    /// The kind of a `Notification`, such as `permission_prompt` or `idle_prompt`.
    public var notificationType: String?
    /// The subagent's type for `SubagentStart` and `SubagentStop`, empty for
    /// the agent Claude Code runs for itself.
    public var agentType: String?
    /// The work still running when a `Stop` comes.
    public var backgroundTasks: [BackgroundTask]?
    /// The app's variables from the hook's environment, added by the hook tool.
    public var environment: HookEnvironment?
    /// The ID of the `claude` process, the hook's parent, added by the hook tool.
    public var processID: Int32?
    /// The tty of the `claude` process, such as `ttys004`, added by the hook tool.
    public var tty: String?

    enum CodingKeys: String, CodingKey {
        case name = "hook_event_name"
        case sessionID = "session_id"
        case folder = "cwd"
        case transcriptPath = "transcript_path"
        case source
        case notificationType = "notification_type"
        case agentType = "agent_type"
        case backgroundTasks = "background_tasks"
        case environment = "env"
        case processID = "claude_pid"
        case tty
    }

    /// One piece of work still running, of which only its type is kept.
    public struct BackgroundTask: Codable, Equatable, Sendable {
        /// The kind of work, such as `subagent`, `workflow`, `teammate` or `shell`.
        public var type: String?
    }

    /// The event in `data`, checked before it is trusted.
    ///
    /// Throws ``HookEventError/tooLarge`` before decoding anything when `data`
    /// is larger than ``maximumSize``. Throws ``HookEventError/malformed``
    /// when it is not a JSON object with the fields' types, when the name or
    /// the session id is empty, or when the process ID is below 1. Fields
    /// outside this type are dropped.
    public static func decode(_ data: Data) throws -> HookEvent {
        let event = try decoded(data, maximumSize: maximumSize)
        guard event.processID ?? 1 > 0 else { throw HookEventError.malformed }
        return event
    }

    /// Claude Code's `event`, trimmed to the fields the app may keep, with
    /// what only the hook tool knows: the app's variables from `environment`,
    /// the `claude` process ID from its `CLAUDE_PID`, and the tty `tty` finds
    /// for that process.
    ///
    /// Throws ``HookEventError/tooLarge`` before decoding anything when
    /// `event` is larger than ``maximumClaudeEventSize``. Throws
    /// ``HookEventError/malformed`` when `CLAUDE_PID` is missing or not a
    /// number above 0, which `tty` is then never asked about, and when `event`
    /// is not a JSON object with the fields' types, or its name or session id
    /// is empty. `env`, `claude_pid` and `tty` in `event` are never taken.
    public init(claudeEvent event: Data, environment: [String: String], tty: (Int32) -> String?) throws {
        guard event.count <= Self.maximumClaudeEventSize else { throw HookEventError.tooLarge }
        guard let processID = environment["CLAUDE_PID"].flatMap(Int32.init), processID > 0 else {
            throw HookEventError.malformed
        }
        self = try Self.decoded(event, maximumSize: Self.maximumClaudeEventSize)
        self.environment = HookEnvironment(environment)
        self.processID = processID
        self.tty = tty(processID)
    }

    private static func decoded(_ data: Data, maximumSize: Int) throws -> HookEvent {
        guard data.count <= maximumSize else { throw HookEventError.tooLarge }
        let event: HookEvent
        do {
            event = try JSONDecoder().decode(HookEvent.self, from: data)
        } catch {
            throw HookEventError.malformed
        }
        guard !event.name.isEmpty, !event.sessionID.isEmpty else { throw HookEventError.malformed }
        return event
    }

    /// The profile folder the session runs under, or `nil` when the event
    /// names none.
    ///
    /// `CLAUDE_CONFIG_DIR` when it is set, otherwise the part of
    /// `transcript_path` before its last `/projects/`, which is
    /// `<profile>/projects/<folder>/<session id>.jsonl`. Every event carries
    /// `transcript_path`, so the default profile normally comes as its path,
    /// `~/.claude`, and `nil` is left for an event without one, which
    /// ``AgentSession/profileName`` shows as the default profile too.
    public var profile: String? {
        if let folder = environment?.configDirectory, !folder.isEmpty {
            return folder
        }
        guard let path = transcriptPath,
              let projects = path.range(of: "/projects/", options: .backwards),
              projects.lowerBound > path.startIndex
        else { return nil }
        return String(path[..<projects.lowerBound])
    }
}

/// The variables the app uses from a hook's environment. The environment as
/// a whole never leaves the hook: it holds tokens.
public struct HookEnvironment: Codable, Equatable, Sendable {
    /// `CLAUDE_CONFIG_DIR`, the profile folder when one was chosen.
    public var configDirectory: String?
    /// `__CFBundleIdentifier`, the terminal app's bundle identifier.
    public var bundleIdentifier: String?
    /// `ITERM_SESSION_ID`, shaped `w0t0p0:<UUID>`, set only in iTerm2.
    public var iTermSessionID: String?

    enum CodingKeys: String, CodingKey {
        case configDirectory = "CLAUDE_CONFIG_DIR"
        case bundleIdentifier = "__CFBundleIdentifier"
        case iTermSessionID = "ITERM_SESSION_ID"
    }

    /// The app's variables among `variables`, such as a process's whole
    /// environment. Every other variable is left out.
    public init(_ variables: [String: String]) {
        configDirectory = variables["CLAUDE_CONFIG_DIR"]
        bundleIdentifier = variables["__CFBundleIdentifier"]
        iTermSessionID = variables["ITERM_SESSION_ID"]
    }
}
