@testable import DontBurnCore
import Foundation
import Testing

/// The row of one session, which runs in `folder` and whose first event has `fields`.
private func row(
    in folder: String = "/code/acme-web", _ fields: [String: Any] = [:], of desk: SessionDesk = SessionDesk(),
) throws -> SessionList.Row {
    var desk = desk
    try desk.send(0, "SessionStart", "web", in: folder, fields)
    return try #require(desk.list(at: 1).rows.first)
}

/// The store that `Sessions.json` holding one finished session with `fields` loads as.
private func stored(_ fields: String) throws -> SessionStore {
    var store = SessionStore()
    try withTemporaryFolder { temporary in
        let session = #"{"tool":"claude","id":"s","folder":"","processID":1,"state":"finished",\#(fields)}"#
        let file = temporary.url.appending(path: SessionStore.fileName)
        try Data(#"{"sessions":[\#(session)]}"#.utf8).write(to: file)
        store = SessionStore.load(in: temporary.url)
    }
    #expect(store.sessions.count == 1)
    return store
}

// MARK: - The title and the color

@Test func `a row has its project's name and its workspace's color, and each session has its own row`() throws {
    var desk = SessionDesk()
    try desk.send(0, "UserPromptSubmit", "web-1")
    try desk.send(1, "UserPromptSubmit", "web-2")
    try desk.send(2, "UserPromptSubmit", "reading", in: "/code/reading-notes")
    let rows = desk.list(at: 3).rows

    #expect(rows.map(\.id) == ["web-1", "web-2", "reading"])
    #expect(rows.map(\.title) == ["Web shop", "Web shop", "Reading"])
    #expect(rows.map(\.color) == [.teal, .teal, .ochre])
}

@Test func `a session in no project has its folder's name and no color`() throws {
    let row = try row(in: "/code/scratch")

    #expect(row.title == "scratch")
    #expect(row.color == nil)
}

@Test func `a project without a name gives the folder's name and still its workspace's color`() throws {
    let desk = SessionDesk()
    desk.projects["/code/acme-web"]?.name = ""
    let row = try row(of: desk)

    #expect(row.title == "acme-web")
    #expect(row.color == .teal)
}

@Test func `a project without a workspace counts as none`() throws {
    var desk = SessionDesk()
    desk.projects["/code/globex-data"]?.workspace = nil
    try desk.send(0, "SessionStart", "globex", in: "/code/globex-data")
    let list = desk.list(at: 1)

    #expect(list.chips.map(\.filter) == [.all, .other])
    #expect(list.rows.map(\.title) == ["globex-data"])
    #expect(list.rows.map(\.color) == [nil])
}

@Test(arguments: [("", ""), ("code/acme-web", "acme-web"), ("/code/acme-web/", "acme-web"), ("/", "/")])
func `the folder's name is the last part of its path, and empty without one`(folder: String, title: String) throws {
    #expect(try row(in: folder).title == title)
}

// MARK: - The profile

@Test(arguments: [
    ("~/.claude", nil),
    ("~/.claude/", nil),
    (".claude", nil),
    ("~/.claude-acme", "acme"),
    ("~/.claude-acme/", "acme"),
    ("~/.claude-globex-2", "globex-2"),
    ("~/.claude--acme", "-acme"),
    // Nothing is left after the prefix, or the prefix is not exactly this.
    ("~/.claude-", ".claude-"),
    ("~/.claudeacme", ".claudeacme"),
    ("~/.claude_acme", ".claude_acme"),
    ("~/.Claude-acme", ".Claude-acme"),
    ("~/claude-acme", "claude-acme"),
    ("~/x.claude-acme", "x.claude-acme"),
    ("~/acme", "acme"),
    // Only the profile's own folder counts.
    ("~/.claude-acme/profile", "profile"),
] as [(String, String?)])
func `the profile is its folder's name without .claude- in front, and none for the default one`(
    folder: String, profile: String?,
) throws {
    let row = try row(in: "/code/acme-web", ["env": ["CLAUDE_CONFIG_DIR": folder]])

    #expect(row.profile == profile)
}

@Test func `a session that names no profile, or stored an empty one, is in the default profile`() throws {
    var replay = SessionReplay()
    try replay.send(0, "SessionStart", without: ["env", "transcript_path"])
    let unnamed = SessionList(sessions: replay.store.sessions, at: HookLine.time(1)) { _ in nil }
    #expect(unnamed.rows.map(\.profile) == [nil])

    let empty = try stored(#""profile":"","lastActivity":0"#)
    let list = SessionList(sessions: empty.sessions, at: HookLine.start) { _ in nil }
    #expect(empty.sessions.first?.profileName.isEmpty == true)
    #expect(list.rows.map(\.profile) == [nil])
}

// MARK: - The terminal

@Test(arguments: [
    ("com.apple.Terminal", "Terminal"),
    ("com.googlecode.iterm2", "iTerm2"),
    ("com.microsoft.VSCode", "VS Code"),
    ("com.todesktop.230313mzl4w4u92", "Cursor"),
    // Unknown, empty, or not exactly one of them.
    ("com.example.terminal", nil),
    ("", nil),
    ("com.apple.terminal", nil),
    (" com.apple.Terminal", nil),
    ("com.googlecode.iterm2.helper", nil),
] as [(String, String?)])
func `the terminal is named by its bundle identifier, and an unknown one has no name`(
    identifier: String, name: String?,
) throws {
    let row = try row(in: "/code/acme-web", ["env": ["__CFBundleIdentifier": identifier]])

    #expect(row.terminal?.name == name)
    #expect(row.title == "Web shop")
}

@Test func `a session outside any terminal has none`() throws {
    #expect(try row(in: "/code/acme-web", ["env": [String: String]()]).terminal == nil)
}

// MARK: - The idle minutes

@Test(arguments: [
    (0.0, 0), (59.9, 0), (60, 1), (119.9, 1), (3599.9, 59), (3600, 60), (86399.9, 1439), (86400, 1440),
])
func `an idle row counts whole minutes since the last activity, rounded down`(
    seconds: TimeInterval, minutes: Int,
) throws {
    var desk = SessionDesk()
    try desk.send(0, "SessionStart", "web")

    #expect(desk.list(at: seconds).rows.map(\.idleMinutes) == [minutes])
}

@Test func `an idle_prompt does not restart the idle minutes`() throws {
    var desk = SessionDesk()
    try desk.send(0, "UserPromptSubmit", "web")
    try desk.send(0, "PermissionRequest", "web")
    try desk.send(180, "Notification", "web", ["notification_type": "idle_prompt"])

    #expect(desk.list(at: 180).rows.map(\.idleMinutes) == [3])
}

@Test func `a row that waits or works has no idle minutes, however long it has`() throws {
    var desk = SessionDesk()
    try desk.send(0, "UserPromptSubmit", "working")
    try desk.send(0, "PermissionRequest", "waiting")

    #expect(desk.list(at: 7200).rows.map(\.idleMinutes) == [nil, nil])
}

@Test func `with the clock moved back an idle row stays, at no minutes`() throws {
    var desk = SessionDesk()
    try desk.send(0, "SessionStart", "web")
    let list = desk.list(at: -3600)

    #expect(list.ids(.idle) == ["web"])
    #expect(list.rows.map(\.idleMinutes) == [0])
}

@Test(arguments: [("-1e300", Int(MenuBarLabel.maximumShownTime) / 60), ("1e300", 0)])
func `a damaged stored time gives the longest time, or none, and never stops the list`(
    time: String, minutes: Int,
) throws {
    let store = try stored(#""lastActivity":\#(time)"#)
    let list = SessionList(sessions: store.sessions, at: HookLine.start) { _ in nil }

    #expect(list.rows.map(\.idleMinutes) == [minutes])
}

// MARK: - Why the list is empty

@Test(arguments: [
    ([], NoSessions.hookNotInstalled),
    ([HookStatus.notInstalled], .hookNotInstalled),
    ([.outOfReach], .hookNotInstalled),
    ([.notInstalled, .outOfReach], .hookNotInstalled),
    ([.installed], .noneRunning),
    ([.foundWithoutRecord], .noneRunning),
    ([.notInstalled, .outOfReach, .installed], .noneRunning),
])
func `the list is empty for want of a hook only when no profile has one`(hooks: [HookStatus], reason: NoSessions) {
    #expect(NoSessions(hooks: hooks) == reason)
}
