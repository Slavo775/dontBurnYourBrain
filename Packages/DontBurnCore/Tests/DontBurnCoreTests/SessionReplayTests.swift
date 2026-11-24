@testable import DontBurnCore
import Foundation
import Testing

// The event orders of `docs/spikes/claude-hook.md`, replayed with the times
// the spike gives, in seconds from the typed prompt. Each test asserts the
// state at the moments the spike names. A stopped turn reads as working
// until the finish delay after its Stop has passed, so those moments are
// written against the delay, and a test also holds just before it ends.

private let typed = ["prompt": "Made-up prompt: add a field to the Acme form"]
private let woken = ["prompt": "<task-notification>made-up</task-notification>"]
private var internalAgent: [String: Any] {
    HookLine.subagent("")
}

private let delay = AgentSession.finishDelay
/// A moment just before a window ends.
private let justBefore = 0.01

@Test func `a plain turn: working, then finished once the finish delay after its Stop has passed`() throws {
    var replay = SessionReplay()
    try replay.send(-30, "SessionStart", ["source": "startup"])
    #expect(replay.state(at: -1) == .registered)

    try replay.send(0, "UserPromptSubmit", typed)
    #expect(replay.state(at: 0) == .working)
    try replay.send(1.5, "Stop", HookLine.tasks())
    #expect(replay.state(at: 1.5) == .working)
    try replay.send(2.5, "SubagentStop", internalAgent)
    #expect(replay.state(at: 1.5 + delay - justBefore) == .working)
    #expect(replay.state(at: 1.5 + delay) == .finished)
    #expect(replay.session()?.lastActivity == HookLine.time(1.5))
}

@Test func `idle_prompt sixty seconds after the last Stop changes nothing`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(1, "Stop", HookLine.tasks())
    try replay.send(61, "Notification", ["notification_type": "idle_prompt", "message": "Made-up notification"])

    #expect(replay.state(at: 61) == .finished)
    #expect(replay.session()?.lastActivity == HookLine.time(1))
}

@Test func `a permission, approved: waiting for you from the request until the turn's Stop`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(2, "PermissionRequest", ["tool_name": "Bash", "tool_input": ["command": "made-up"]])
    #expect(replay.state(at: 2) == .waitingForYou)
    try replay.send(10, "Notification", ["notification_type": "permission_prompt"])
    #expect(replay.state(at: 10) == .waitingForYou)
    // The user says "Yes" at +15. No event comes for it.
    #expect(replay.state(at: 18) == .waitingForYou)

    try replay.send(20, "Stop", HookLine.tasks())
    #expect(replay.state(at: 20 + delay - justBefore) == .working)
    #expect(replay.state(at: 20 + delay) == .finished)
}

@Test func `a permission, denied: waiting for you until idle_prompt finishes the turn`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(2, "PermissionRequest", ["tool_name": "Bash"])
    try replay.send(8, "Notification", ["notification_type": "permission_prompt"])
    // The user says "No". No Stop comes.
    #expect(replay.state(at: 120) == .waitingForYou)

    try replay.send(180, "Notification", ["notification_type": "idle_prompt"])
    #expect(replay.state(at: 180) == .finished)
    #expect(replay.session()?.lastActivity == HookLine.time(8))
}

@Test func `after an Esc the session stays working until its next event, the accepted limit`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    // Esc at +2. No event at all, and no idle_prompt within two minutes.
    #expect(replay.state(at: 120) == .working)
    #expect(replay.state(at: 3600) == .working)

    try replay.send(3600, "UserPromptSubmit", typed)
    try replay.send(3601, "Stop", HookLine.tasks())
    #expect(replay.state(at: 3601 + delay) == .finished)
}

@Test func `case a: two background subagents keep the session working until the Stop that lists none`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(1, "PreToolUse", ["tool_name": "Agent"])
    try replay.send(2, "SubagentStart", HookLine.subagent("general-purpose", id: "agent-a"))
    try replay.send(2, "PostToolUse", ["tool_name": "Agent", "tool_response": ["status": "async_launched"]])
    try replay.send(2, "SubagentStart", HookLine.subagent("general-purpose", id: "agent-b"))
    try replay.send(3, "Stop", HookLine.tasks("subagent", "subagent"))
    try replay.send(4, "SubagentStop", internalAgent)
    #expect(replay.state(at: 20) == .working)

    try replay.send(34, "SubagentStop", HookLine.subagent("general-purpose", id: "agent-a"))
    try replay.send(34, "UserPromptSubmit", woken)
    try replay.send(35, "Stop", HookLine.tasks("subagent"))
    try replay.send(36, "SubagentStop", internalAgent)
    #expect(replay.state(at: 45) == .working)

    try replay.send(49, "SubagentStop", HookLine.subagent("general-purpose", id: "agent-b"))
    try replay.send(49, "UserPromptSubmit", woken)
    try replay.send(50, "Stop", HookLine.tasks())
    try replay.send(51, "SubagentStop", internalAgent)
    #expect(replay.state(at: 50 + delay - justBefore) == .working)
    #expect(replay.state(at: 50 + delay) == .finished)
    #expect(replay.session()?.lastActivity == HookLine.time(50))
}

@Test func `the background-shell variant finishes at the first Stop, and works again for each woken turn`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(2, "SubagentStart", HookLine.subagent("general-purpose", id: "agent-a"))
    try replay.send(2, "SubagentStart", HookLine.subagent("general-purpose", id: "agent-b"))
    try replay.send(6, "Stop", HookLine.tasks("shell", "shell"))
    try replay.send(7, "SubagentStop", internalAgent)
    #expect(replay.state(at: 6 + delay) == .finished)
    #expect(replay.state(at: 20) == .finished)

    for (shellEnd, agent) in [(33.0, "agent-a"), (44.0, "agent-b")] {
        try replay.send(shellEnd, "SubagentStart", HookLine.subagent("general-purpose", id: agent))
        #expect(replay.state(at: shellEnd) == .finished)
        try replay.send(shellEnd, "SubagentStop", HookLine.subagent("general-purpose", id: agent))
        try replay.send(shellEnd, "UserPromptSubmit", woken)
        #expect(replay.state(at: shellEnd + 1) == .working)
        try replay.send(shellEnd + 2, "Stop", agent == "agent-a" ? HookLine.tasks("shell") : HookLine.tasks())
        #expect(replay.state(at: shellEnd + 2 + delay - justBefore) == .working)
        #expect(replay.state(at: shellEnd + 2 + delay) == .finished)
    }
}

@Test func `case b: a foreground subagent works through quiet seconds and finishes after its Stop`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(1, "PreToolUse", ["tool_name": "Agent", "tool_input": ["run_in_background": false]])
    try replay.send(1, "SubagentStart", HookLine.subagent("general-purpose"))
    #expect(replay.state(at: 23) == .working)

    try replay.send(24, "SubagentStop", HookLine.subagent("general-purpose"))
    try replay.send(24, "PostToolUse", ["tool_name": "Agent", "tool_response": ["status": "completed"]])
    try replay.send(25, "Stop", HookLine.tasks())
    try replay.send(26, "SubagentStop", internalAgent)
    #expect(replay.state(at: 25 + delay - justBefore) == .working)
    #expect(replay.state(at: 25 + delay) == .finished)
}

@Test func `case c: exit while a background subagent works makes the session gone, and prune drops it`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(1, "SubagentStart", HookLine.subagent("general-purpose"))
    try replay.send(2, "Stop", HookLine.tasks("subagent"))
    try replay.send(4, "SubagentStop", internalAgent)
    // /exit opens a dialog at +13. No event until "Exit and stop tasks".
    #expect(replay.state(at: 30) == .working)

    try replay.send(42, "SessionEnd", ["reason": "prompt_input_exit"])
    #expect(replay.state(at: 42) == .gone)
    #expect(replay.state(at: 42)?.group == nil)
    replay.store.prune { _ in true }
    #expect(replay.store.sessions.isEmpty)
}

@Test(arguments: ["prompt_input_exit", "other"])
func `the end: SessionEnd from exit or a closed tab makes a session gone`(reason: String) throws {
    var replay = SessionReplay()
    try replay.send(0, "SessionStart", ["source": "startup"])
    try replay.send(5, "UserPromptSubmit", typed)
    try replay.send(6, "Stop", HookLine.tasks())
    try replay.send(7, "SessionEnd", ["reason": reason])

    #expect(replay.state(at: 7) == .gone)
}

/// The spike saw the other subagent's turn start "two seconds later", in a log
/// that counts whole seconds, so the gap may be anything below three.
@Test(arguments: [1.0, 2.0, 2.5, 2.9])
func `two subagents that finish close together do not make the state flicker`(gap: TimeInterval) throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(3, "Stop", HookLine.tasks("subagent", "subagent"))
    try replay.send(40, "UserPromptSubmit", woken)
    try replay.send(41, "Stop", HookLine.tasks())
    for moment in stride(from: 41, through: 41 + gap, by: 0.1) {
        #expect(replay.state(at: moment) == .working, "\(moment)")
    }

    try replay.send(41 + gap, "UserPromptSubmit", woken)
    #expect(replay.state(at: 41 + gap) == .working)
    try replay.send(42 + gap, "Stop", HookLine.tasks())
    #expect(replay.state(at: 42 + gap + delay - justBefore) == .working)
    #expect(replay.state(at: 42 + gap + delay) == .finished)
}

@Test func `a Stop inside the window of an earlier Stop starts the window again`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(1, "Stop", HookLine.tasks())
    try replay.send(2, "Stop", HookLine.tasks())

    #expect(replay.state(at: 1 + delay) == .working)
    #expect(replay.state(at: 2 + delay - justBefore) == .working)
    #expect(replay.state(at: 2 + delay) == .finished)
}

@Test func `a Stop that lists a subagent inside the window of an earlier Stop keeps the session working`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(1, "Stop", HookLine.tasks())
    try replay.send(2, "Stop", HookLine.tasks("subagent"))

    #expect(replay.state(at: 60) == .working)
}

@Test func `idle_prompt inside the window of a Stop leaves the window as it is`() throws {
    var replay = SessionReplay()
    try replay.send(0, "UserPromptSubmit", typed)
    try replay.send(1, "Stop", HookLine.tasks())
    try replay.send(1 + delay / 2, "Notification", ["notification_type": "idle_prompt"])

    #expect(replay.state(at: 1 + delay - justBefore) == .working)
    #expect(replay.state(at: 1 + delay) == .finished)
    #expect(replay.session()?.lastActivity == HookLine.time(1))
}
