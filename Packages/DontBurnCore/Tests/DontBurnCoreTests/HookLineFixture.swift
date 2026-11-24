@testable import DontBurnCore
import Foundation

/// Neutral hook lines, shaped like the ones the spike recorded in
/// `docs/spikes/claude-hook.md`. No real path, profile or prompt: the session
/// ids are made up, the folders are the sample ones, and every content field
/// holds an obviously made-up text that tests show is dropped.
enum HookLine {
    static let acme = "00000000-0000-4000-8000-000000000001"
    static let globex = "00000000-0000-4000-8000-000000000002"
    /// iTerm2's UUID for the Acme session's tab.
    static let acmeTab = "11111111-2222-4333-8444-555555555555"
    /// 2026-01-15 08:41:30 UTC. Seconds in the tests count from it, as the spike counts from the prompt.
    static let start = Date(timeIntervalSince1970: 1_768_466_490)

    static func time(_ seconds: TimeInterval) -> Date {
        start.addingTimeInterval(seconds)
    }

    /// The Acme session in iTerm2 under the profile `~/.claude-acme`, run by
    /// `claude` process 30002 on `ttys004`, with `fields` on top and the keys
    /// in `without` left out.
    static func data(
        _ name: String,
        _ fields: [String: Any] = [:],
        session: String = acme,
        without: Set<String> = [],
    ) throws -> Data {
        var object: [String: Any] = [
            "hook_event_name": name,
            "session_id": session,
            "cwd": "/code/acme-web",
            "transcript_path": "~/.claude-acme/projects/-code-acme-web/\(session).jsonl",
            "scratchpad_dir": "/tmp/claude-scratchpad",
            "claude_pid": 30002,
            "tty": "ttys004",
            "env": [
                "CLAUDE_CONFIG_DIR": "~/.claude-acme",
                "__CFBundleIdentifier": "com.googlecode.iterm2",
                "ITERM_SESSION_ID": "w0t1p0:\(acmeTab)",
            ],
        ]
        object.merge(fields) { $1 }
        for key in without {
            object.removeValue(forKey: key)
        }
        return try JSONSerialization.data(withJSONObject: object, options: .sortedKeys)
    }

    static func event(
        _ name: String,
        _ fields: [String: Any] = [:],
        session: String = acme,
        without: Set<String> = [],
    ) throws -> HookEvent {
        try HookEvent.decode(data(name, fields, session: session, without: without))
    }

    /// A `background_tasks` list with one running entry per type.
    static func tasks(_ types: String...) -> [String: Any] {
        tasks(types)
    }

    static func tasks(_ types: [String]) -> [String: Any] {
        let entries = types.enumerated().map { index, type in
            ["id": "task-\(index)", "type": type, "status": "running", "agent_type": "general-purpose"]
        }
        return ["background_tasks": entries, "last_assistant_message": "Made-up answer about the Acme shop"]
    }

    /// A subagent's own event, from a subagent of type `agentType`. Empty for
    /// the agent Claude Code runs for itself after a `Stop`.
    static func subagent(_ agentType: String, id: String = "agent-a") -> [String: Any] {
        ["agent_id": id, "agent_type": agentType]
    }
}

/// A store fed hook lines at seconds counted from ``HookLine/start``.
struct SessionReplay {
    var store = SessionStore()

    mutating func send(
        _ seconds: TimeInterval,
        _ name: String,
        _ fields: [String: Any] = [:],
        session: String = HookLine.acme,
        without: Set<String> = [],
    ) throws {
        try store.apply(HookLine.event(name, fields, session: session, without: without), at: HookLine.time(seconds))
    }

    func session(_ id: String = HookLine.acme) -> AgentSession? {
        store.sessions.first { $0.id == id }
    }

    func state(at seconds: TimeInterval, of id: String = HookLine.acme) -> AgentSessionState? {
        session(id)?.state(at: HookLine.time(seconds))
    }
}
