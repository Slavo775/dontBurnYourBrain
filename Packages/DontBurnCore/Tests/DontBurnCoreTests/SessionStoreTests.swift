@testable import DontBurnCore
import Foundation
import Testing

/// A session that was registered at +0 and is working since +1.
private func workingSession() throws -> SessionReplay {
    var replay = SessionReplay()
    try replay.send(0, "SessionStart", ["source": "startup"])
    try replay.send(1, "UserPromptSubmit", ["prompt": "Made-up prompt"])
    return replay
}

// MARK: - Which event leads to which state

@Test func `with no events, the store is empty, and pruning it keeps it empty`() {
    var store = SessionStore()
    #expect(store.sessions.isEmpty)

    store.prune { _ in true }
    #expect(store.sessions.isEmpty)
}

@Test(arguments: [
    ("SessionStart", ["source": "startup"], AgentSessionState.registered),
    ("SessionStart", ["source": "resume"], .registered),
    ("SessionStart", ["source": "clear"], .registered),
    ("SessionStart", ["source": "fork"], .registered),
    ("SessionStart", [:], .registered),
    ("SessionStart", ["source": "compact"], .working),
    ("UserPromptSubmit", [:], .working),
    ("PermissionRequest", [:], .waitingForYou),
    ("Notification", ["notification_type": "permission_prompt"], .waitingForYou),
    ("Notification", ["notification_type": "idle_prompt"], .finished),
    ("Notification", ["notification_type": "auth_success"], .working),
    ("Notification", ["notification_type": "elicitation_dialog"], .working),
    ("Notification", [:], .working),
    ("SubagentStart", ["agent_type": "Explore"], .working),
    ("SubagentStop", ["agent_type": "Explore"], .working),
    ("SessionEnd", ["reason": "other"], .gone),
])
func `each event leads a working session to the state the phase 0 table names`(
    name: String,
    fields: [String: String],
    expected: AgentSessionState,
) throws {
    var replay = try workingSession()
    try replay.send(10, name, fields)

    #expect(replay.state(at: 10) == expected)
}

@Test(arguments: [
    (["subagent"], AgentSessionState.working),
    (["workflow"], .working),
    (["teammate"], .working),
    (["shell", "subagent"], .working),
    (["monitor", "teammate"], .working),
    ([], .finished),
    (["shell"], .finished),
    (["shell", "monitor", "cloud session", "MCP task"], .finished),
])
func `a Stop or StopFailure keeps a session working only while a subagent, a workflow or a teammate runs`(
    types: [String],
    expected: AgentSessionState,
) throws {
    for name in ["Stop", "StopFailure"] {
        var replay = try workingSession()
        let fields = name == "Stop" ? HookLine.tasks(types) : HookLine.tasks(types).merging(["error": "made-up"]) { $1 }
        try replay.send(10, name, fields)

        #expect(replay.state(at: 60) == expected, "\(name) \(types)")
    }
}

@Test func `a Stop with no background_tasks, or entries with no type, finishes the turn`() throws {
    var replay = try workingSession()
    try replay.send(10, "Stop", without: ["background_tasks"])
    #expect(replay.state(at: 60) == .finished)

    try replay.send(70, "UserPromptSubmit")
    try replay.send(71, "Stop", ["background_tasks": [["status": "running"]]])
    #expect(replay.state(at: 80) == .finished)
}

@Test(arguments: [AgentSessionState.registered, .finished, .gone])
func `idle_prompt finishes only a working or waiting session`(state: AgentSessionState) throws {
    var replay = SessionReplay()
    try replay.send(0, "SessionStart", ["source": "startup"])
    if state == .finished {
        try replay.send(1, "UserPromptSubmit")
        try replay.send(2, "Stop", HookLine.tasks())
    } else if state == .gone {
        try replay.send(2, "SessionEnd", ["reason": "other"])
    }
    let before = try #require(replay.session())
    try replay.send(62, "Notification", ["notification_type": "idle_prompt"])

    #expect(replay.state(at: 62) == state)
    #expect(replay.session() == before)
}

@Test(arguments: ["auth_success", "elicitation_dialog", ""])
func `auth_success and other notifications change nothing, not even the last activity`(type: String) throws {
    var replay = try workingSession()
    let before = try #require(replay.session())
    try replay.send(10, "Notification", ["notification_type": type])
    try replay.send(11, "Notification", without: ["notification_type"])

    #expect(replay.session() == before)
}

@Test func `a SubagentStart or SubagentStop with an empty or missing agent type is ignored`() throws {
    var replay = try workingSession()
    try replay.send(5, "Stop", HookLine.tasks())
    let before = try #require(replay.session())
    for name in ["SubagentStart", "SubagentStop"] {
        try replay.send(6, name, HookLine.subagent(""))
        try replay.send(6, name, without: ["agent_type"])
        try replay.send(6, name, HookLine.subagent(""), session: HookLine.globex)
    }

    #expect(replay.session() == before)
    #expect(replay.store.sessions.count == 1)
}

@Test func `subagent events with an agent type are activity and change no state`() throws {
    var replay = try workingSession()
    try replay.send(5, "Stop", HookLine.tasks())
    try replay.send(6, "SubagentStop", HookLine.subagent("Explore"))

    // The subagent's event does not move the end of the Stop's window.
    #expect(replay.session()?.lastActivity == HookLine.time(6))
    #expect(replay.state(at: 5 + AgentSession.finishDelay - 0.01) == .working)
    #expect(replay.state(at: 5 + AgentSession.finishDelay) == .finished)
}

@Test func `events the app does not use change nothing, even for a session it has not seen`() throws {
    var replay = try workingSession()
    let before = try #require(replay.session())
    for name in ["PreToolUse", "PostToolUse", "PreCompact", "MadeUpEvent"] {
        try replay.send(10, name, ["tool_name": "Bash"])
        try replay.send(10, name, session: HookLine.globex)
    }

    #expect(replay.store.sessions == [before])
}

@Test func `an event without the claude process ID changes nothing`() throws {
    var replay = try workingSession()
    let before = try #require(replay.session())
    try replay.send(10, "Stop", HookLine.tasks(), without: ["claude_pid"])
    try replay.send(10, "SessionStart", session: HookLine.globex, without: ["claude_pid"])

    #expect(replay.store.sessions == [before])
}

@Test func `a SessionEnd for a session it has not seen adds nothing`() throws {
    var replay = SessionReplay()
    try replay.send(0, "SessionEnd", ["reason": "other"])

    #expect(replay.store.sessions.isEmpty)
}

@Test(arguments: [
    ("UserPromptSubmit", [:], AgentSessionState.working),
    ("PermissionRequest", [:], .waitingForYou),
    ("Notification", ["notification_type": "permission_prompt"], .waitingForYou),
    ("Notification", ["notification_type": "idle_prompt"], .registered),
    ("SubagentStop", ["agent_type": "Explore"], .registered),
    ("Stop", [:], .finished),
])
func `any other event the app uses adds a session it has not seen`(
    name: String,
    fields: [String: String],
    expected: AgentSessionState,
) throws {
    var replay = SessionReplay()
    try replay.send(10, name, fields)

    #expect(replay.store.sessions.map(\.id) == [HookLine.acme])
    #expect(replay.state(at: 20) == expected)
    #expect(replay.session()?.lastActivity == HookLine.time(10))
}

@Test func `sessions are kept apart by their session id, oldest first`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit")
    try replay.send(1, "PermissionRequest", ["cwd": "/code/globex-data", "claude_pid": 30102], session: HookLine.globex)

    #expect(replay.store.sessions.map(\.id) == [HookLine.acme, HookLine.globex])
    #expect(replay.state(at: 5) == .working)
    #expect(replay.state(at: 5, of: HookLine.globex) == .waitingForYou)
}

// MARK: - What is kept per session

@Test func `a session keeps the tool, profile, folder, terminal and tab handle of its first event`() throws {
    var replay = SessionReplay()
    try replay.send(0, "SessionStart", ["source": "startup"])
    try replay.send(1, "UserPromptSubmit", ["cwd": "/code/acme-web/src", "tty": "ttys009", "env": [
        "CLAUDE_CONFIG_DIR": "~/.claude-globex", "__CFBundleIdentifier": "com.apple.Terminal",
    ]])
    let session = try #require(replay.session())

    #expect(session.tool == .claude)
    #expect(session.id == HookLine.acme)
    #expect(session.profile == "~/.claude-acme")
    #expect(session.profileName == ".claude-acme")
    #expect(session.folder == "/code/acme-web")
    #expect(session.folderName == "acme-web")
    #expect(session.terminalBundleIdentifier == "com.googlecode.iterm2")
    #expect(session.processID == 30002)
    #expect(session.tty == "ttys004")
    #expect(session.tabID == HookLine.acmeTab)
    #expect(session.lastActivity == HookLine.time(1))
}

@Test func `a session that comes back with a new claude process takes that process's details`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit")
    try replay.send(1, "Stop", HookLine.tasks())
    try replay.send(600, "SessionStart", [
        "source": "resume", "claude_pid": 31007, "tty": "ttys011", "cwd": "/code/acme-web/api",
        "env": ["__CFBundleIdentifier": "com.apple.Terminal"],
    ])
    let session = try #require(replay.session())

    #expect(replay.store.sessions.count == 1)
    #expect(replay.state(at: 600) == .registered)
    #expect(session.processID == 31007)
    #expect(session.tty == "ttys011")
    #expect(session.folder == "/code/acme-web/api")
    #expect(session.terminalBundleIdentifier == "com.apple.Terminal")
    #expect(session.tabID == nil)
    #expect(session.profile == "~/.claude-acme")
}

@Test func `the tab handle is the tty with the claude process ID, plus iTerm2's UUID after the colon`() throws {
    var replay = SessionReplay()
    try replay.send(0, "SessionStart")
    let terminalApp = ["env": ["__CFBundleIdentifier": "com.apple.Terminal"]]
    try replay.send(0, "SessionStart", terminalApp, session: HookLine.globex)
    try replay.send(0, "SessionStart", ["claude_pid": 30202], session: "unknown-terminal", without: ["env", "tty"])
    let terminal = try #require(replay.session(HookLine.globex))
    let unknown = try #require(replay.session("unknown-terminal"))

    #expect(replay.session()?.tabID == HookLine.acmeTab)
    #expect(terminal.tty == "ttys004")
    #expect(terminal.processID == 30002)
    #expect(terminal.tabID == nil)
    #expect(unknown.terminalBundleIdentifier == nil)
    #expect(unknown.tty == nil)
    #expect(unknown.tabID == nil)
}

@Test func `a tty given to a new tab names another session, and the old one goes when its process does`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit")
    // The Acme tab closes, and a new tab gets its tty at once.
    try replay.send(30, "SessionStart", ["claude_pid": 30102, "cwd": "/code/globex-data"], session: HookLine.globex)
    #expect(replay.store.sessions.map(\.tty) == ["ttys004", "ttys004"])

    replay.store.prune { $0.processID == 30102 }
    #expect(replay.store.sessions.map(\.id) == [HookLine.globex])
}

@Test(arguments: [
    ("w0t1p0:\(HookLine.acmeTab)", HookLine.acmeTab),
    ("w12t3p1:aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee", "aaaaaaaa-bbbb-4ccc-8ddd-eeeeeeeeeeee"),
    ("w0t1p0", nil),
    (HookLine.acmeTab, nil),
    ("", nil),
    ("w0t1p0:", nil),
    ("w0t1p0:made-up-tab", nil),
    ("w0t1p0:\(HookLine.acmeTab):made-up", nil),
] as [(String, String?)])
func `the tab ID is the UUID after the colon in ITERM_SESSION_ID, and nothing else is one`(
    value: String,
    tabID: String?,
) throws {
    var replay = SessionReplay()
    let environment = ["__CFBundleIdentifier": "com.googlecode.iterm2", "ITERM_SESSION_ID": value]
    try replay.send(0, "SessionStart", ["env": environment])

    #expect(replay.session()?.tabID == tabID)
}

@Test func `a SessionEnd from another claude process leaves the session as it is, and its own ends it`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit")
    // The session is resumed in a second tab while its first tab stays open.
    let secondTab: [String: Any] = [
        "claude_pid": 31007, "tty": "ttys011", "env": ["__CFBundleIdentifier": "com.apple.Terminal"],
    ]
    try replay.send(10, "SessionStart", secondTab.merging(["source": "resume"]) { $1 })
    try replay.send(11, "UserPromptSubmit", secondTab)
    try replay.send(12, "Stop", secondTab.merging(HookLine.tasks()) { $1 })
    let before = try #require(replay.session())

    // The first tab closes.
    try replay.send(13, "SessionEnd", ["reason": "other"])
    #expect(replay.session() == before)
    #expect(replay.state(at: 13) == .working)
    #expect(replay.state(at: 12 + AgentSession.finishDelay) == .finished)
    #expect(before.processID == 31007)
    #expect(before.tty == "ttys011")
    #expect(before.lastActivity == HookLine.time(12))

    try replay.send(60, "SessionEnd", secondTab.merging(["reason": "prompt_input_exit"]) { $1 })
    #expect(replay.state(at: 60) == .gone)
}

@Test func `a profile is shown by its folder's name, and the default one as .claude`() throws {
    var replay = SessionReplay()
    try replay.send(0, "SessionStart", ["env": ["CLAUDE_CONFIG_DIR": "~/.claude-acme/"]])
    try replay.send(0, "SessionStart", [
        "env": [String: String](), "transcript_path": "~/.claude/projects/-code-globex-data/\(HookLine.globex).jsonl",
    ], session: HookLine.globex)
    try replay.send(0, "SessionStart", session: "default", without: ["env", "transcript_path"])

    #expect(replay.session()?.profileName == ".claude-acme")
    #expect(replay.session(HookLine.globex)?.profileName == ".claude")
    #expect(replay.session("default")?.profile == nil)
    #expect(replay.session("default")?.profileName == ".claude")
}

// MARK: - Leaving the list

@Test func `prune drops gone sessions and sessions whose process is not alive, and keeps the rest`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit")
    try replay.send(9, "Stop", HookLine.tasks())
    try replay.send(0, "SessionStart", ["claude_pid": 30102], session: HookLine.globex)
    try replay.send(5, "SessionEnd", ["claude_pid": 30102], session: HookLine.globex)
    try replay.send(0, "PermissionRequest", ["claude_pid": 30202], session: "dead")
    var asked: [String] = []

    // At +10 the Acme session is still inside the window of its Stop.
    replay.store.prune { session in
        asked.append(session.id)
        return session.processID != 30202
    }

    #expect(replay.store.sessions.map(\.id) == [HookLine.acme])
    #expect(replay.state(at: 10) == .working)
    #expect(asked.contains(HookLine.acme))
    #expect(asked.contains("dead"))
}

@Test func `the states fall into Needs you, Working and Idle, and gone into none`() {
    #expect(AgentSessionState.waitingForYou.group == .needsYou)
    #expect(AgentSessionState.working.group == .working)
    #expect(AgentSessionState.registered.group == .idle)
    #expect(AgentSessionState.finished.group == .idle)
    #expect(AgentSessionState.gone.group == nil)
}
