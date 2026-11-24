@testable import DontBurnCore
import Foundation
import Testing

/// Made-up content Claude Code puts into events. None of it may reach the app.
private let madeUpContent = [
    "Made-up prompt: refactor the Acme checkout",
    "made-up-tool-input",
    "Made-up answer about the Acme shop",
    "Made-up permission suggestion",
    "Made-up notification message",
    "Made-up API error",
    "made-up-messaging-token",
    "made-up-ancestor",
]

/// Every content field and every variable the hook must never send, as
/// Claude Code would hand them to it.
private var everythingClaudeCodeSends: [String: Any] {
    [
        "prompt": madeUpContent[0],
        "prompt_id": "prompt-1",
        "permission_mode": "default",
        "tool_name": "Bash",
        "tool_input": ["command": "echo \(madeUpContent[1])"],
        "tool_response": ["stdout": madeUpContent[1]],
        "last_assistant_message": madeUpContent[2],
        "permission_suggestions": [["rule": madeUpContent[3]]],
        "message": madeUpContent[4],
        "error": madeUpContent[5],
        "reason": "other",
        "model": "made-up-model",
        "background_tasks": [["id": "task-0", "type": "shell", "status": "running", "agent_type": "Explore"]],
        "env": [
            "CLAUDE_CONFIG_DIR": "~/.claude-acme",
            "__CFBundleIdentifier": "com.googlecode.iterm2",
            "ITERM_SESSION_ID": "w0t1p0:\(HookLine.acmeTab)",
            "CLAUDE_CODE_MESSAGING_TOKEN": madeUpContent[6],
            "TERM_PROGRAM": "iTerm.app",
            "PATH": "/usr/bin:/bin",
        ],
        "ancestors": [["pid": 30001, "tty": "ttys004", "comm": madeUpContent[7]]],
    ]
}

private func text(of value: some Encodable) throws -> String {
    try #require(String(bytes: JSONEncoder().encode(value), encoding: .utf8))
}

private func keys(of data: Data) throws -> Set<String> {
    try Set(#require(JSONSerialization.jsonObject(with: data) as? [String: Any]).keys)
}

// MARK: - Checked before it is trusted

@Test func `an event larger than the maximum size is refused before it is decoded`() throws {
    let base = try HookLine.data("UserPromptSubmit", ["prompt": ""])
    let padding = String(repeating: "x", count: HookEvent.maximumSize - base.count)
    let atLimit = try HookLine.data("UserPromptSubmit", ["prompt": padding])
    let overLimit = try HookLine.data("UserPromptSubmit", ["prompt": padding + "x"])

    #expect(atLimit.count == HookEvent.maximumSize)
    #expect(try HookEvent.decode(atLimit).name == "UserPromptSubmit")
    #expect(throws: HookEventError.tooLarge) { try HookEvent.decode(overLimit) }
    // Not JSON at all, so only a check made before decoding can call it too large.
    #expect(throws: HookEventError.tooLarge) {
        try HookEvent.decode(Data(repeating: 0xFF, count: HookEvent.maximumSize + 1))
    }
}

@Test(arguments: [
    "",
    "not json",
    "[]",
    "\"Stop\"",
    "null",
    "{}",
    #"{"hook_event_name":"Stop"}"#,
    #"{"session_id":"00000000-0000-4000-8000-000000000001"}"#,
    #"{"hook_event_name":"Stop","session_id":42}"#,
    #"{"hook_event_name":["Stop"],"session_id":"s"}"#,
    #"{"hook_event_name":"Stop","session_id":"s","claude_pid":"30002"}"#,
    #"{"hook_event_name":"Stop","session_id":"s","claude_pid":1.5}"#,
    #"{"hook_event_name":"Stop","session_id":"s","claude_pid":2147483648}"#,
    #"{"hook_event_name":"Stop","session_id":"s","background_tasks":{"type":"subagent"}}"#,
    #"{"hook_event_name":"Stop","session_id":"s","background_tasks":[{"type":7}]}"#,
    #"{"hook_event_name":"Stop","session_id":"s","env":"CLAUDE_CONFIG_DIR=~/.claude-acme"}"#,
    #"{"hook_event_name":"Stop","session_id":"s","cwd":["/code/acme-web"]}"#,
    #"{"hook_event_name":"Stop","session_id":"s""#,
])
func `an event that is not a JSON object of the expected shape is refused`(line: String) {
    #expect(throws: HookEventError.malformed) { try HookEvent.decode(Data(line.utf8)) }
}

@Test func `an event with an empty name or session id, or a process ID below 1, is refused`() throws {
    let refused: [[String: Any]] = [
        ["hook_event_name": ""], ["session_id": ""], ["claude_pid": 0], ["claude_pid": -30002],
    ]
    for fields in refused {
        #expect(throws: HookEventError.malformed, "\(fields)") { try HookLine.event("Stop", fields) }
    }
    #expect(try HookLine.event("Stop", ["claude_pid": 1]).processID == 1)
    #expect(try HookLine.event("Stop", without: ["claude_pid"]).processID == nil)
}

@Test func `the fields kept from an event are the ones the app uses, under Claude Code's own names`() throws {
    let event = try HookLine.event("SessionStart", ["source": "startup"])

    #expect(event.name == "SessionStart")
    #expect(event.sessionID == HookLine.acme)
    #expect(event.folder == "/code/acme-web")
    #expect(event.transcriptPath == "~/.claude-acme/projects/-code-acme-web/\(HookLine.acme).jsonl")
    #expect(event.source == "startup")
    #expect(event.processID == 30002)
    #expect(event.tty == "ttys004")
    #expect(event.environment?.bundleIdentifier == "com.googlecode.iterm2")
    #expect(try HookLine.event("Notification", ["notification_type": "idle_prompt"]).notificationType == "idle_prompt")
    #expect(try HookLine.event("SubagentStop", HookLine.subagent("Explore")).agentType == "Explore")
    #expect(try HookLine.event("Stop", HookLine.tasks("subagent", "shell")).backgroundTasks?.map(\.type) == [
        "subagent", "shell",
    ])
}

// MARK: - Nothing outside the allowed list

@Test func `fields outside the allowed list are dropped, so a prompt and a tool input never reach the event`() throws {
    let allowed: Set = [
        "hook_event_name", "session_id", "cwd", "transcript_path", "source", "notification_type",
        "agent_type", "background_tasks", "env", "claude_pid", "tty",
    ]
    for name in ["UserPromptSubmit", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"] {
        let event = try HookLine.event(name, everythingClaudeCodeSends)
        let encoded = try JSONEncoder().encode(event)
        let saved = try text(of: event)

        #expect(try keys(of: encoded).isSubset(of: allowed), "\(name)")
        #expect(try keys(of: JSONEncoder().encode(event.environment)) == [
            "CLAUDE_CONFIG_DIR", "__CFBundleIdentifier", "ITERM_SESSION_ID",
        ])
        #expect(try keys(of: JSONEncoder().encode(event.backgroundTasks?.first)) == ["type"])
        for content in madeUpContent {
            #expect(!saved.contains(content), "\(name): \(content)")
        }
    }
}

@Test func `a session saved from events holds no prompt, tool input or other content`() throws {
    try withTemporaryFolder { temporary in
        var replay = SessionReplay()
        let names = ["SessionStart", "UserPromptSubmit", "PermissionRequest", "Notification", "Stop"]
        for (second, name) in names.enumerated() {
            try replay.send(TimeInterval(second), name, everythingClaudeCodeSends)
        }
        try replay.store.save(in: temporary.url)
        let file = try Data(contentsOf: temporary.url.appending(path: SessionStore.fileName))
        let saved = try #require(String(bytes: file, encoding: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: file) as? [String: Any])
        let sessions = try #require(object["sessions"] as? [[String: Any]])

        #expect(sessions.count == 1)
        #expect(Set(sessions[0].keys).isSubset(of: [
            "tool", "id", "profile", "folder", "terminalBundleIdentifier", "processID", "tty", "tabID",
            "lastActivity", "state", "workingUntil",
        ]))
        // JSONEncoder writes a slash as \/, so the transcript path is looked for by its words.
        let leftOut = ["transcript_path", "projects", "-code-acme-web", "scratchpad", "made-up-model", "Bash"]
        for content in madeUpContent + leftOut {
            #expect(!saved.contains(content), "\(content)")
        }
    }
}

@Test func `the environment keeps only CLAUDE_CONFIG_DIR, __CFBundleIdentifier and ITERM_SESSION_ID`() throws {
    let environment = HookEnvironment([
        "CLAUDE_CONFIG_DIR": "~/.claude-acme",
        "__CFBundleIdentifier": "com.apple.Terminal",
        "ITERM_SESSION_ID": "w0t1p0:\(HookLine.acmeTab)",
        "CLAUDE_CODE_MESSAGING_TOKEN": "made-up-messaging-token",
        "VSCODE_GIT_IPC_AUTH_TOKEN": "made-up-ipc-token",
        "TERM_SESSION_ID": "made-up-term-session",
        "CLAUDE_PID": "30002",
    ])

    #expect(environment.configDirectory == "~/.claude-acme")
    #expect(environment.bundleIdentifier == "com.apple.Terminal")
    #expect(environment.iTermSessionID == "w0t1p0:\(HookLine.acmeTab)")
    #expect(try !text(of: environment).contains("made-up"))
    #expect(try text(of: HookEnvironment([:])) == "{}")
}

// MARK: - The profile

@Test func `the profile is CLAUDE_CONFIG_DIR when it is set, whatever the transcript path says`() throws {
    let event = try HookLine.event("SessionStart", [
        "env": ["CLAUDE_CONFIG_DIR": "~/.claude-globex"],
        "transcript_path": "~/.claude-acme/projects/-code-acme-web/\(HookLine.acme).jsonl",
    ])

    #expect(event.profile == "~/.claude-globex")
}

@Test func `otherwise the profile is the part of transcript_path before its last projects folder`() throws {
    let noEnvironment = try HookLine.event("SessionStart", without: ["env"])
    let unset = try HookLine.event("SessionStart", ["env": [String: String]()])
    let empty = try HookLine.event("SessionStart", ["env": ["CLAUDE_CONFIG_DIR": ""]])
    let nested = try HookLine.event("SessionStart", [
        "env": [String: String](),
        "transcript_path": "~/projects/.claude-globex/projects/-code-globex-data/\(HookLine.acme).jsonl",
    ])

    #expect(noEnvironment.profile == "~/.claude-acme")
    #expect(unset.profile == "~/.claude-acme")
    #expect(empty.profile == "~/.claude-acme")
    #expect(nested.profile == "~/projects/.claude-globex")
}

@Test func `otherwise the profile is the default one`() throws {
    let noTranscript = try HookLine.event("SessionStart", without: ["env", "transcript_path"])
    #expect(noTranscript.profile == nil)
    let paths = [
        "~/.claude-acme/sessions/\(HookLine.acme).jsonl",
        "/projects/-code-acme-web/\(HookLine.acme).jsonl",
        "",
    ]
    for path in paths {
        let event = try HookLine.event("SessionStart", ["env": [String: String](), "transcript_path": path])
        #expect(event.profile == nil, "\(path)")
    }
}
