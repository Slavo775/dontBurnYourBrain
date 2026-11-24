import DontBurnCore
import Foundation
import Testing

/// The hook tool's whole environment, as Claude Code would start it in iTerm2,
/// with variables that must never leave the tool.
private let toolEnvironment = [
    "CLAUDE_PID": "30002",
    "CLAUDE_CONFIG_DIR": "~/.claude-acme",
    "__CFBundleIdentifier": "com.googlecode.iterm2",
    "ITERM_SESSION_ID": "w0t1p0:\(HookLine.acmeTab)",
    "CLAUDE_CODE_MESSAGING_TOKEN": "made-up-messaging-token",
    "PATH": "/usr/bin:/bin:/made-up-path",
    "HOME": "/made-up-home",
    "TERM_SESSION_ID": "made-up-term-session",
]

/// Claude Code's raw event: what it hands the hook on standard input, which
/// carries no `env`, `claude_pid` or `tty`, with `fields` on top.
private func raw(_ name: String, _ fields: [String: Any] = [:]) throws -> Data {
    var object = everythingClaudeCodeSends
    object.removeValue(forKey: "env")
    object.removeValue(forKey: "ancestors")
    object.merge([
        "hook_event_name": name,
        "session_id": HookLine.acme,
        "cwd": "/code/acme-web",
        "transcript_path": "~/.claude-acme/projects/-code-acme-web/\(HookLine.acme).jsonl",
    ]) { $1 }
    object.merge(fields) { $1 }
    return try JSONSerialization.data(withJSONObject: object)
}

/// A tty closure that records each process ID it is asked about.
private final class TerminalLookup {
    var asked: [Int32] = []
    let answer: String?

    init(answer: String? = "ttys004") {
        self.answer = answer
    }

    func name(ofProcess processID: Int32) -> String? {
        asked.append(processID)
        return answer
    }
}

// MARK: - The hook tool trims Claude Code's event

@Test func `the tool sends only the allowed fields and variables, whatever Claude Code's event carries`() throws {
    let allowed: Set = [
        "hook_event_name", "session_id", "cwd", "transcript_path", "source", "notification_type",
        "agent_type", "background_tasks", "env", "claude_pid", "tty",
    ]
    for name in ["UserPromptSubmit", "PermissionRequest", "Notification", "Stop", "StopFailure", "SessionEnd"] {
        let lookup = TerminalLookup()
        let event = try HookEvent(claudeEvent: raw(name), environment: toolEnvironment, tty: lookup.name(ofProcess:))
        let message = try JSONEncoder().encode(event)
        let object = try #require(JSONSerialization.jsonObject(with: message) as? [String: Any])
        let text = try #require(String(bytes: message, encoding: .utf8))

        #expect(Set(object.keys).isSubset(of: allowed), "\(name)")
        #expect(try Set(#require(object["env"] as? [String: Any]).keys) == [
            "CLAUDE_CONFIG_DIR", "__CFBundleIdentifier", "ITERM_SESSION_ID",
        ])
        #expect(!text.contains("made-up"), "\(name)")
        for content in madeUpContent {
            #expect(!text.contains(content), "\(name): \(content)")
        }
    }
}

@Test func `the tool takes env, claude_pid and tty from what it knows, never from Claude Code's event`() throws {
    let lookup = TerminalLookup(answer: "ttys009")
    let event = try HookEvent(
        claudeEvent: raw("Stop", [
            "env": ["CLAUDE_CONFIG_DIR": "~/.claude-acme", "ITERM_SESSION_ID": "w0t1p0:\(HookLine.acmeTab)"],
            "claude_pid": -1,
            "tty": "ttys004",
        ]),
        environment: [
            "CLAUDE_PID": "30003",
            "CLAUDE_CONFIG_DIR": "~/.claude-globex",
            "__CFBundleIdentifier": "com.apple.Terminal",
        ],
        tty: lookup.name(ofProcess:),
    )

    #expect(event.processID == 30003)
    #expect(event.tty == "ttys009")
    #expect(lookup.asked == [30003])
    #expect(event.environment == HookEnvironment([
        "CLAUDE_CONFIG_DIR": "~/.claude-globex", "__CFBundleIdentifier": "com.apple.Terminal",
    ]))
    #expect(event.environment?.iTermSessionID == nil)
}

@Test func `a claude process without a tty sends no tty`() throws {
    let event = try HookEvent(
        claudeEvent: raw("Stop", ["tty": "ttys004"]),
        environment: toolEnvironment,
        tty: TerminalLookup(answer: nil).name(ofProcess:),
    )

    #expect(event.tty == nil)
    #expect(event.processID == 30002)
}

@Test(arguments: [nil, "", "0", "-1", "-30002", "abc", "30002abc", " 30002", "1.5", "2147483648"] as [String?])
func `without a CLAUDE_PID above 0 the tool sends nothing, and never looks up a tty`(processID: String?) throws {
    var environment = toolEnvironment
    environment["CLAUDE_PID"] = processID
    let lookup = TerminalLookup()

    #expect(throws: HookEventError.malformed) {
        try HookEvent(claudeEvent: raw("Stop"), environment: environment, tty: lookup.name(ofProcess:))
    }
    #expect(lookup.asked.isEmpty)
}

@Test(arguments: [
    "", "not json", "[]", "{}", "null",
    #"{"hook_event_name":"","session_id":"00000000-0000-4000-8000-000000000001"}"#,
    #"{"hook_event_name":"Stop","session_id":""}"#,
    #"{"hook_event_name":["Stop"],"session_id":"00000000-0000-4000-8000-000000000001"}"#,
    #"{"hook_event_name":"Stop","session_id":"00000000-0000-4000-8000-000000000001","cwd":7}"#,
])
func `an event from Claude Code of the wrong shape is refused, and no tty is looked up`(line: String) {
    let lookup = TerminalLookup()

    #expect(throws: HookEventError.malformed) {
        try HookEvent(claudeEvent: Data(line.utf8), environment: toolEnvironment, tty: lookup.name(ofProcess:))
    }
    #expect(lookup.asked.isEmpty)
}

@Test func `an event from Claude Code of exactly 16 MB is taken, and one byte more is refused unread`() throws {
    let base = try raw("PermissionRequest", ["tool_input": ["content": ""]])
    let padding = String(repeating: "x", count: HookEvent.maximumClaudeEventSize - base.count)
    let atLimit = try raw("PermissionRequest", ["tool_input": ["content": padding]])
    let overLimit = try raw("PermissionRequest", ["tool_input": ["content": padding + "x"]])
    let lookup = TerminalLookup()

    #expect(atLimit.count == HookEvent.maximumClaudeEventSize)
    let event = try HookEvent(claudeEvent: atLimit, environment: toolEnvironment, tty: lookup.name(ofProcess:))
    #expect(event.name == "PermissionRequest")
    #expect(try JSONEncoder().encode(event).count < HookEvent.maximumSize)
    #expect(lookup.asked == [30002])

    for tooLarge in [overLimit, Data(repeating: 0xFF, count: HookEvent.maximumClaudeEventSize + 1)] {
        #expect(throws: HookEventError.tooLarge) {
            try HookEvent(claudeEvent: tooLarge, environment: toolEnvironment, tty: lookup.name(ofProcess:))
        }
    }
    #expect(lookup.asked == [30002])
}

// MARK: - The app receives the tool's message

@Test func `what the tool sends for a large permission request, the app takes as a session waiting for you`() throws {
    let largeInput = ["content": String(repeating: "made-up-tool-input ", count: 20000)]
    let event = try HookEvent(
        claudeEvent: raw("PermissionRequest", ["tool_input": largeInput]),
        environment: toolEnvironment,
        tty: TerminalLookup().name(ofProcess:),
    )
    let message = try JSONEncoder().encode(event)
    var store = SessionStore()

    #expect(message.count < HookEvent.maximumSize)
    #expect(try store.receive(message, at: HookLine.start) == event)
    let session = try #require(store.sessions.first)
    #expect(session.id == HookLine.acme)
    #expect(session.state(at: HookLine.start) == .waitingForYou)
    #expect(session.profile == "~/.claude-acme")
    #expect(session.terminalBundleIdentifier == "com.googlecode.iterm2")
    #expect(session.processID == 30002)
    #expect(session.tty == "ttys004")
    #expect(session.tabID == HookLine.acmeTab)
}

@Test func `a message that is too large or has the wrong shape is refused, and the store stays as it was`() throws {
    var store = SessionStore()
    try store.receive(HookLine.data("UserPromptSubmit"), at: HookLine.start)
    let before = store
    let base = try HookLine.data("Stop", ["error": ""])
    let padding = String(repeating: "x", count: HookEvent.maximumSize - base.count + 1)
    let tooLarge = try HookLine.data("Stop", ["error": padding])

    #expect(tooLarge.count == HookEvent.maximumSize + 1)
    #expect(throws: HookEventError.tooLarge) { try store.receive(tooLarge, at: HookLine.time(5)) }
    #expect(throws: HookEventError.tooLarge) {
        try store.receive(Data(repeating: 0xFF, count: HookEvent.maximumSize + 1), at: HookLine.time(5))
    }
    let wrongShapes = try [
        Data(), Data("not json".utf8), Data("[]".utf8),
        HookLine.data("Stop", ["claude_pid": -1]), HookLine.data("Stop", ["claude_pid": "30002"]),
        HookLine.data(""), HookLine.data("Stop", ["session_id": ""]),
        HookLine.data("SessionEnd", ["env": "CLAUDE_CONFIG_DIR=~/.claude-acme"]),
    ]
    for message in wrongShapes {
        #expect(throws: HookEventError.malformed) { try store.receive(message, at: HookLine.time(5)) }
    }
    #expect(store == before)

    // The channel goes on: the next good message is applied.
    #expect(try store.receive(HookLine.data("PermissionRequest"), at: HookLine.time(6)).name == "PermissionRequest")
    #expect(store.sessions.first?.state(at: HookLine.time(6)) == .waitingForYou)
}
