@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// Two sessions, one working inside the window of a Stop and one waiting for
/// you, with times that have fractions of a second.
private func twoSessions() throws -> SessionStore {
    var replay = SessionReplay()
    try replay.send(0.125, "UserPromptSubmit")
    try replay.send(1.375, "Stop", HookLine.tasks())
    let globex: [String: Any] = ["claude_pid": 30102, "cwd": "/code/globex-data"]
    try replay.send(0.5, "PermissionRequest", globex, session: HookLine.globex)
    return replay.store
}

private func sessionsFile(in folder: TemporaryFolder) -> URL {
    folder.url.appending(path: SessionStore.fileName)
}

// MARK: - The sessions file

@Test func `save then load gives the same sessions, states and times`() throws {
    try withTemporaryFolder { temporary in
        let store = try twoSessions()
        try store.save(in: temporary.url)
        let loaded = SessionStore.load(in: temporary.url)

        #expect(loaded == store)
        #expect(loaded.sessions.map { $0.state(at: HookLine.time(2)) } == [.working, .waitingForYou])
        #expect(loaded.sessions.map { $0.state(at: HookLine.time(3.375)) } == [.finished, .waitingForYou])
        #expect(loaded.sessions.first?.lastActivity == HookLine.time(1.375))
    }
}

@Test func `save writes Sessions.json into the folder it is given, and a new save replaces it`() throws {
    try withTemporaryFolder { temporary in
        let folder = temporary.url.appending(path: "Store/Deeper", directoryHint: .isDirectory)
        try twoSessions().save(in: folder)
        #expect(SessionStore.load(in: folder).sessions.count == 2)

        try SessionStore().save(in: folder)
        #expect(SessionStore.load(in: folder).sessions.isEmpty)
        let written = try FileManager.default.contentsOfDirectory(atPath: temporary.path("Store/Deeper"))
        #expect(written == ["Sessions.json"])
    }
}

@Test func `a folder with no sessions file, or no folder at all, loads as an empty store`() throws {
    try withTemporaryFolder { temporary in
        let empty = SessionStore.load(in: temporary.url)
        let missing = SessionStore.load(in: temporary.url.appending(path: "Missing"))
        let left = try FileManager.default.contentsOfDirectory(atPath: temporary.path)

        #expect(empty.sessions.isEmpty)
        #expect(missing.sessions.isEmpty)
        #expect(left.isEmpty)
    }
}

@Test func `a file up to the maximum size loads, and one byte more loads as an empty store`() throws {
    try withTemporaryFolder { temporary in
        try twoSessions().save(in: temporary.url)
        let file = sessionsFile(in: temporary)
        let saved = try Data(contentsOf: file)
        // JSON allows white space after the value, so the padded file is still the same sessions.
        let padded = saved + Data(repeating: 0x20, count: SessionStore.maximumFileSize - saved.count)

        try padded.write(to: file)
        #expect(SessionStore.load(in: temporary.url).sessions.count == 2)

        try (padded + Data([0x20])).write(to: file)
        #expect(SessionStore.load(in: temporary.url).sessions.isEmpty)
    }
}

@Test(arguments: [
    "",
    "not json",
    "[]",
    "{}",
    #"{"sessions":{}}"#,
    #"{"sessions":[{"id":"00000000-0000-4000-8000-000000000001"}]}"#,
    #"{"sessions":[{"tool":"codex","id":"s","folder":"","processID":1,"lastActivity":0,"state":"working"}]}"#,
    #"{"sessions":[{"tool":"claude","id":"s","folder":"","processID":1,"lastActivity":0,"state":"asleep"}]}"#,
    #"{"sessions":["#,
])
func `a file that cannot be decoded loads as an empty store`(contents: String) throws {
    try withTemporaryFolder { temporary in
        try Data(contents.utf8).write(to: sessionsFile(in: temporary))

        #expect(SessionStore.load(in: temporary.url).sessions.isEmpty)
    }
}

@Test func `a file holding more than a session's own fields loads, and the rest is dropped`() throws {
    try withTemporaryFolder { temporary in
        let session = #"{"tool":"claude","id":"s","folder":"","processID":1,"lastActivity":0,"state":"working""#
        let file = #"{"sessions":["# + session + #","prompt":"Made-up prompt"}],"other":"made-up"}"#
        try Data(file.utf8).write(to: sessionsFile(in: temporary))
        let loaded = SessionStore.load(in: temporary.url)
        try loaded.save(in: temporary.url)

        #expect(loaded.sessions.map(\.id) == ["s"])
        #expect(loaded.sessions.first?.state(at: HookLine.start) == .working)
        let saved = try #require(String(bytes: Data(contentsOf: sessionsFile(in: temporary)), encoding: .utf8))
        #expect(!saved.contains("ade-up"))
    }
}

@Test func `a folder named like the sessions file loads as an empty store`() throws {
    try withTemporaryFolder { temporary in
        try temporary.make(SessionStore.fileName)

        #expect(SessionStore.load(in: temporary.url).sessions.isEmpty)
    }
}

@Test func `after a restart, sessions whose claude process is gone are dropped`() throws {
    try withTemporaryFolder { temporary in
        try twoSessions().save(in: temporary.url)
        var restarted = SessionStore.load(in: temporary.url)
        restarted.prune { $0.processID == 30102 }

        #expect(restarted.sessions.map(\.id) == [HookLine.globex])
    }
}

// MARK: - The project

/// Acme's Web shop with its folder in a local store in memory, and Personal's
/// Side project with the root folder, which holds every absolute path.
private struct FolderDesk {
    let context: ModelContext
    let folders: ProjectFolders
    let webShop: Project
    let sideProject: Project

    init(rootFolderForSideProject: Bool = false) throws {
        context = try ModelContext(ModelStore.localInMemory())
        folders = ProjectFolders(context: context)
        webShop = Project(name: "Web shop", workspace: Workspace(name: "Acme", color: .teal))
        sideProject = Project(name: "Side project", workspace: Workspace(name: "Personal", color: .ochre, sortOrder: 2))
        try folders.add("/code/acme-web", to: webShop, among: projects)
        if rootFolderForSideProject {
            try folders.add("/", to: sideProject, among: projects)
        }
    }

    var projects: [Project] {
        [webShop, sideProject]
    }

    func project(of session: AgentSession?) throws -> String? {
        try #require(session).project(in: folders, among: projects)?.name
    }
}

@Test func `a session's project comes from the folder rule, and a folder in no project's has none (Other)`() throws {
    let desk = try FolderDesk()
    var replay = SessionReplay()
    try replay.send(0, "SessionStart", ["cwd": "/code/acme-web/src"])
    try replay.send(0, "SessionStart", ["cwd": "/code/globex-data", "claude_pid": 30102], session: HookLine.globex)

    #expect(try desk.project(of: replay.session()) == "Web shop")
    #expect(try desk.project(of: replay.session(HookLine.globex)) == nil)
}

@Test(arguments: ["", "code/acme-web", "acme-web", ".", "~/code/acme-web", nil])
func `a session with an empty or relative folder has no project (Other), even under a root project folder`(
    folder: String?,
) throws {
    let desk = try FolderDesk(rootFolderForSideProject: true)
    var replay = SessionReplay()
    if let folder {
        try replay.send(0, "SessionStart", ["cwd": folder])
    } else {
        try replay.send(0, "SessionStart", without: ["cwd"])
    }
    try replay.send(0, "SessionStart", ["cwd": "/code/notes", "claude_pid": 30102], session: HookLine.globex)

    #expect(replay.session()?.folder == folder ?? "")
    #expect(try desk.project(of: replay.session()) == nil)
    #expect(try desk.project(of: replay.session(HookLine.globex)) == "Side project")
}

@Test func `a folder given to a project after the session started counts at once`() throws {
    let desk = try FolderDesk()
    var replay = SessionReplay()
    try replay.send(0, "SessionStart", ["cwd": "/code/notes/today"])
    #expect(try desk.project(of: replay.session()) == nil)

    try desk.folders.add("/code/notes", to: desk.sideProject, among: desk.projects)
    #expect(try desk.project(of: replay.session()) == "Side project")
}
