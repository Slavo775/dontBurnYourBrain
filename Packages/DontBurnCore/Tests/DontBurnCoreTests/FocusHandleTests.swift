@testable import DontBurnCore
import Foundation
import Testing

private let terminalApp = "com.apple.Terminal"
private let iTerm2App = "com.googlecode.iterm2"
private let visualStudioCodeApp = "com.microsoft.VSCode"
private let cursorApp = "com.todesktop.230313mzl4w4u92"

/// The Acme session, run by `claude` process 30002 on `ttys004` in the
/// terminal `bundleIdentifier`, with iTerm2's tab ID unless `tabID` is false.
private func session(in bundleIdentifier: String?, tty: Bool = true, tabID: Bool = true) throws -> AgentSession {
    var environment: [String: Any] = [:]
    environment["__CFBundleIdentifier"] = bundleIdentifier
    environment["ITERM_SESSION_ID"] = tabID ? "w0t1p0:\(HookLine.acmeTab)" : nil
    var replay = SessionReplay()
    try replay.send(0, "SessionStart", ["env": environment], without: tty ? [] : ["tty"])
    return try #require(replay.session())
}

/// The one session that `Sessions.json` holding a session with `fields` decodes as.
private func decoded(_ fields: String) throws -> AgentSession {
    let session = #"{"tool":"claude","id":"s","folder":"","state":"working","lastActivity":0,\#(fields)}"#
    let store = try JSONDecoder().decode(SessionStore.self, from: Data(#"{"sessions":[\#(session)]}"#.utf8))
    return try #require(store.sessions.first)
}

// MARK: - The tty's name

@Test(arguments: ["ttys000", "ttys004", "ttys511", "ttys999"])
func `a tty's name is ttys and three digits`(name: String) {
    #expect(FocusHandle.isTTYName(name))
}

@Test(arguments: [
    "", "ttys", "ttys04", "ttys0004", "/dev/ttys004", "TTYS004", "Ttys004", "ttyp004", "ttys00a", "ttys-04",
    "ttys 04", " ttys004", "ttys004 ", "ttys004\n", "ttys00\n", "ttys00\"", "ttys\"04", "ttys00\u{0}",
    "ttys\u{0660}\u{0660}\u{0664}", "ttys00\u{FF14}", "ttys004\u{301}", "console",
])
func `nothing else is a tty's name, not another path, case, digit or character`(name: String) {
    #expect(!FocusHandle.isTTYName(name))
}

// MARK: - The handle per terminal

@Test func `an iTerm2 session is found by iTerm2's tab ID, not by its tty`() throws {
    let handle = try session(in: iTerm2App).focusHandle

    #expect(handle == .iTerm2(sessionID: HookLine.acmeTab))
    #expect(handle?.terminal == .iTerm2)
}

@Test func `an iTerm2 session with a tty but no tab ID has no handle`() throws {
    #expect(try session(in: iTerm2App, tabID: false).focusHandle == nil)
}

@Test(arguments: [true, false])
func `a Terminal tab is found by its tty, and an inherited tab ID is ignored`(tabID: Bool) throws {
    let handle = try session(in: terminalApp, tabID: tabID).focusHandle

    #expect(handle == .terminal(tty: "ttys004"))
    #expect(handle?.terminal == .terminal)
}

@Test func `a Terminal tab without a tty has no handle`() throws {
    #expect(try session(in: terminalApp, tty: false).focusHandle == nil)
}

@Test(arguments: [visualStudioCodeApp, cursorApp, "com.example.terminal", "", nil] as [String?])
func `a session in VS Code, Cursor, an unknown terminal or none has no handle, even with a tty and a tab ID`(
    bundleIdentifier: String?,
) throws {
    let session = try session(in: bundleIdentifier)

    #expect(session.tty == "ttys004")
    #expect(session.focusHandle == nil)
}

@Test(arguments: [
    #""ttys004""#, #""ttys04""#, #""/dev/ttys004""#, #""ttys004\n""#, #""ttys004\" & quit""#, #""""#,
])
func `a Terminal tty read back from the file is taken only in a tty's shape`(tty: String) throws {
    let session = try decoded(#""processID":30002,"terminalBundleIdentifier":"\#(terminalApp)","tty":\#(tty)"#)

    #expect(session.focusHandle == (tty == #""ttys004""# ? .terminal(tty: "ttys004") : nil))
}

@Test(arguments: [
    (HookLine.acmeTab, true), (HookLine.acmeTab.lowercased(), true), ("made-up-tab", false),
    ("{\(HookLine.acmeTab)}", false), ("\(HookLine.acmeTab)\" & quit", false), ("", false),
] as [(String, Bool)])
func `an iTerm2 tab ID read back from the file is taken only when it is a UUID`(tabID: String, taken: Bool) throws {
    let quoted = try #require(String(bytes: JSONEncoder().encode(tabID), encoding: .utf8))
    let session = try decoded(#""processID":30002,"terminalBundleIdentifier":"\#(iTerm2App)","tabID":\#(quoted)"#)

    #expect(session.focusHandle == (taken ? .iTerm2(sessionID: tabID) : nil))
}

// MARK: - The tty is still the session's

@Test func `a tty is the session's while its claude process holds it, and the lookup asks for that process`() throws {
    var asked: [Int32] = []
    let held = try session(in: terminalApp).stillHoldsTTY { processID in
        asked.append(processID)
        return "ttys004"
    }

    #expect(held)
    #expect(asked == [30002])
}

@Test(arguments: [nil, "ttys005", "ttys0040", "/dev/ttys004", ""] as [String?])
func `a closed tab or a dead process, which has no tty, and a process on another tty never hold it`(
    lookedUp: String?,
) throws {
    #expect(try !session(in: terminalApp).stillHoldsTTY { _ in lookedUp })
}

@Test func `a session without a tty, or with no claude process, never holds one, and nothing is looked up`() throws {
    let noTTY = try session(in: terminalApp, tty: false)
    let noProcess = try decoded(#""processID":0,"terminalBundleIdentifier":"\#(terminalApp)","tty":"ttys004""#)
    let negative = try decoded(#""processID":-1,"terminalBundleIdentifier":"\#(terminalApp)","tty":"ttys004""#)

    for session in [noTTY, noProcess, negative] {
        var asked = false
        #expect(!session.stillHoldsTTY { _ in
            asked = true
            return "ttys004"
        })
        #expect(!asked)
    }
}

@Test func `a process that is gone has no tty, and a running one has none or one in a tty's shape`() {
    // macOS gives out process IDs up to 99,999.
    #expect(TerminalDevice.name(ofProcess: Int32.max) == nil)
    #expect(TerminalDevice.name(ofProcess: -1) == nil)
    #expect(TerminalDevice.name(ofProcess: getpid()).map(FocusHandle.isTTYName) ?? true)
}

// MARK: - The Focus button on the row

@Test(arguments: [
    ("PermissionRequest", SessionGroup.needsYou), ("UserPromptSubmit", .working), ("SessionStart", .idle),
] as [(String, SessionGroup)])
func `a row has Focus in every group, for Terminal and iTerm2 only, and not for a terminal macOS refused`(
    event: String,
    group: SessionGroup,
) throws {
    var desk = SessionDesk()
    let terminals: [(id: String, app: String?)] = [
        ("iterm2", iTerm2App), ("terminal", terminalApp), ("vscode", visualStudioCodeApp), ("cursor", cursorApp),
        ("none", nil),
    ]
    for terminal in terminals {
        var environment: [String: Any] = ["ITERM_SESSION_ID": "w0t1p0:\(HookLine.acmeTab)"]
        environment["__CFBundleIdentifier"] = terminal.app
        try desk.send(0, event, terminal.id, ["env": environment])
    }
    func canFocus(denied: Set<TerminalApp>) throws -> [String: Bool] {
        let list = SessionList(sessions: desk.replay.store.sessions, automationDenied: denied, at: HookLine.time(10)) {
            desk.projects[$0.folder]
        }
        #expect(list.sections.map(\.group) == [group])
        return Dictionary(uniqueKeysWithValues: list.rows.map { ($0.id, $0.canFocus) })
    }

    let none = ["vscode": false, "cursor": false, "none": false]
    #expect(try canFocus(denied: []) == none.merging(["iterm2": true, "terminal": true]) { $1 })
    #expect(try canFocus(denied: [.iTerm2]) == none.merging(["iterm2": false, "terminal": true]) { $1 })
    #expect(try canFocus(denied: [.terminal]) == none.merging(["iterm2": true, "terminal": false]) { $1 })
    #expect(try canFocus(denied: [.iTerm2, .terminal]) == none.merging(["iterm2": false, "terminal": false]) { $1 })
    #expect(try canFocus(denied: [.visualStudioCode, .cursor]) == none.merging(["iterm2": true, "terminal": true]) {
        $1
    })
}

@Test func `a row whose session has no handle has no Focus, even in Terminal or iTerm2`() throws {
    var desk = SessionDesk()
    try desk.send(0, "SessionStart", "iterm2", ["env": ["__CFBundleIdentifier": iTerm2App]])
    let terminal: [String: Any] = ["cwd": "/code/acme-web", "env": ["__CFBundleIdentifier": terminalApp]]
    try desk.replay.send(0, "SessionStart", terminal, session: "terminal", without: ["tty"])

    #expect(desk.list(at: 1).rows.map(\.canFocus) == [false, false])
}

// MARK: - What macOS answered

@Test(arguments: [
    (0, AutomationPermission.allowed), (-1743, .denied), (-1744, .notAsked), (-600, .notRunning),
    (-1712, .unknown), (-609, .unknown), (-1, .unknown), (1, .unknown), (-1745, .unknown), (Int32.min, .unknown),
    (Int32.max, .unknown),
] as [(Int32, AutomationPermission)])
func `each permission status the app knows has its own answer, and any other is unknown`(
    status: Int32,
    permission: AutomationPermission,
) {
    #expect(AutomationPermission(status: status) == permission)
}

@Test func `a focus is in front only when the script found the tab, and gone when it did not`() {
    #expect(FocusOutcome(found: true, errorNumber: nil) == .focused)
    #expect(FocusOutcome(found: false, errorNumber: nil) == .gone)
}

@Test(arguments: [
    (-1743, FocusOutcome.denied), (-1712, .timedOut), (-600, .gone), (-609, .gone), (0, .failed(0)),
    (-1728, .failed(-1728)), (-10004, .failed(-10004)),
] as [(Int, FocusOutcome)])
func `each Apple event error has its outcome, whatever the script answered`(errorNumber: Int, outcome: FocusOutcome) {
    #expect(FocusOutcome(found: true, errorNumber: errorNumber) == outcome)
    #expect(FocusOutcome(found: false, errorNumber: errorNumber) == outcome)
}

// MARK: - A session whose tab is gone

@Test func `forgetting a session drops only that one, and its next event adds it again`() throws {
    var replay = SessionReplay()
    try replay.send(0, "SessionStart")
    try replay.send(1, "SessionStart", session: HookLine.globex)
    try replay.send(2, "SessionStart", session: "third")

    replay.store.forget(HookLine.globex)
    #expect(replay.store.sessions.map(\.id) == [HookLine.acme, "third"])

    replay.store.forget("unknown")
    #expect(replay.store.sessions.map(\.id) == [HookLine.acme, "third"])

    try replay.send(3, "UserPromptSubmit", session: HookLine.globex)
    #expect(replay.store.sessions.map(\.id) == [HookLine.acme, "third", HookLine.globex])
}
