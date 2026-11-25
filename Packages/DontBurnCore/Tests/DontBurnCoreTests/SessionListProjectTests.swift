@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// The sample set in memory, and its projects' folders below `/code` in a
/// local store in memory. Side project's folder lies inside Web shop's.
private struct ProjectDesk {
    let context: ModelContext
    let folders: ProjectFolders
    var replay = SessionReplay()

    init() throws {
        context = try ModelContext(ModelStore.inMemory())
        try SampleData.seed(into: context, now: HookLine.start)
        folders = try ProjectFolders(context: ModelContext(ModelStore.localInMemory()))
        for (name, folder) in [
            "Web shop": "/code/acme-web", "Data platform": "/code/globex-data",
            "Side project": "/code/acme-web/side", "Reading": "/code/reading-notes",
        ] {
            try folders.add(folder, to: project(name), among: projects())
        }
    }

    func projects() throws -> [Project] {
        try context.fetch(FetchDescriptor<Project>())
    }

    func project(_ name: String) throws -> Project {
        try #require(projects().first { $0.name == name })
    }

    /// Sends the event `name` of a session in `folder`, named after its folder.
    mutating func send(_ seconds: TimeInterval, _ name: String, in folder: String) throws {
        try replay.send(seconds, name, ["cwd": folder], session: folder.isEmpty ? "none" : folder)
    }

    func list(at seconds: TimeInterval, filter: SessionFilter = .all) throws -> SessionList {
        let projects = try projects()
        return try SessionList(sessions: replay.store.sessions, filter: filter, at: HookLine.time(seconds)) {
            try $0.project(in: folders, among: projects)
        }
    }
}

/// One session in each group and workspace, and one in no project.
private func fourSessions() throws -> ProjectDesk {
    var desk = try ProjectDesk()
    try desk.send(0, "PermissionRequest", in: "/code/acme-web")
    try desk.send(1, "UserPromptSubmit", in: "/code/globex-data")
    try desk.send(2, "SessionStart", in: "/code/reading-notes")
    try desk.send(3, "SessionStart", in: "/code/scratch")
    return desk
}

// MARK: - Which project a session is listed under

@Test func `a session is listed under the project with the deepest folder, and through it under a workspace`() throws {
    var desk = try ProjectDesk()
    try desk.send(0, "UserPromptSubmit", in: "/code/acme-web/src")
    try desk.send(1, "UserPromptSubmit", in: "/code/acme-web/side/app")
    let list = try desk.list(at: 2)

    #expect(list.rows.map(\.title) == ["Web shop", "Side project"])
    #expect(list.rows.map(\.color) == [.teal, .ochre])
    #expect(list.chips.map(\.workspaceName) == [nil, "Acme", "Personal"])
}

@Test func `the sessions of an archived project, and of an archived workspace, go to Other`() throws {
    let desk = try fourSessions()
    let reading = try desk.project("Reading")
    let globex = try #require(desk.project("Data platform").workspace)
    #expect(try desk.list(at: 4, filter: .workspace(globex.id)).filter == .workspace(globex.id))

    reading.isArchived = true
    globex.isArchived = true
    let list = try desk.list(at: 4, filter: .workspace(globex.id))

    #expect(list.filter == .all)
    #expect(list.chips.map(\.workspaceName) == [nil, "Acme", nil])
    #expect(list.chips.map(\.count) == [4, 1, 3])
    #expect(list.rows.map(\.title) == ["Web shop", "globex-data", "scratch", "reading-notes"])
}

@Test(arguments: [("", ""), ("code/acme-web", "acme-web"), (".", "."), ("~/code/acme-web", "acme-web")])
func `a session with an empty or relative folder is listed under Other, by its folder's name`(
    folder: String, title: String,
) throws {
    var desk = try ProjectDesk()
    try desk.send(0, "SessionStart", in: folder)
    let list = try desk.list(at: 1)

    #expect(list.chips.map(\.filter) == [.all, .other])
    #expect(list.rows.map(\.title) == [title])
}

@Test func `without projects, as without a store, every session is under Other and in the same group`() throws {
    let desk = try fourSessions()
    let sessions = desk.replay.store.sessions
    let withProjects = try desk.list(at: 4)
    let noStore = SessionList(sessions: sessions, at: HookLine.time(4)) { _ in nil }
    let noProjects = try SessionList(sessions: sessions, at: HookLine.time(4)) {
        try $0.project(in: desk.folders, among: [])
    }

    #expect(noStore == noProjects)
    #expect(noStore.chips.map(\.filter) == [.all, .other])
    #expect(noStore.chips.map(\.count) == [4, 4])
    #expect(noStore.sections.map { $0.rows.map(\.id) } == withProjects.sections.map { $0.rows.map(\.id) })
    #expect(noStore.rows.map(\.title) == ["acme-web", "globex-data", "scratch", "reading-notes"])
}

@Test func `an error from finding a project is passed on, and no project is asked for an ended session`() throws {
    var desk = try ProjectDesk()
    try desk.send(0, "SessionStart", in: "/code/acme-web")
    try desk.send(1, "SessionEnd", in: "/code/acme-web")
    let sessions = desk.replay.store.sessions
    let ended = try SessionList(sessions: sessions, at: HookLine.time(2)) { _ in throw ProjectFolderError.notAbsolute }
    #expect(ended.isEmpty)

    try desk.send(3, "SessionStart", in: "/code/globex-data")
    #expect(throws: ProjectFolderError.notAbsolute) {
        try SessionList(sessions: desk.replay.store.sessions, at: HookLine.time(4)) { _ in
            throw ProjectFolderError.notAbsolute
        }
    }
}

// MARK: - The timer and the list

@Test func `a session of a project whose time is not tracked is listed, and no block or entry is made for it`() throws {
    var desk = try ProjectDesk()
    let entryIDs = try Set(entries(desk.context).map(\.id))
    let blockIDs = try Set(blocks(desk.context).map(\.id))
    let personal = try #require(desk.project("Reading").workspace)
    #expect(try !desk.project("Reading").isTimeTracked)

    for (seconds, name, group) in [
        (0.0, "SessionStart", SessionGroup.idle),
        (1, "UserPromptSubmit", .working),
        (2, "PermissionRequest", .needsYou),
    ] {
        try desk.send(seconds, name, in: "/code/reading-notes")
        for filter in [SessionFilter.all, .workspace(personal.id)] {
            let list = try desk.list(at: seconds, filter: filter)
            #expect(list.sections.map(\.group) == [group])
            #expect(list.rows.map(\.title) == ["Reading"])
            #expect(list.rows.map(\.color) == [.ochre])
            #expect(list.chips.map(\.workspaceName) == [nil, "Personal"])
        }
    }

    #expect(!desk.context.hasChanges)
    #expect(try Set(entries(desk.context).map(\.id)) == entryIDs)
    #expect(try Set(blocks(desk.context).map(\.id)) == blockIDs)
}

@Test(arguments: TimerScenario.allCases)
func `the list is the same whatever the timer does, and changes nothing the timer keeps`(
    scenario: TimerScenario,
) throws {
    let desk = try fourSessions()
    let before = try desk.list(at: 4)
    try scenario.apply(to: desk.context, now: HookLine.start)
    try desk.context.save()
    let status = try TimerEngine(context: desk.context).settle(at: HookLine.start)
    let entryCount = try entries(desk.context).count

    let list = try desk.list(at: 4)

    #expect(list.sections == before.sections)
    #expect(list.chips.map(\.filter) == before.chips.map(\.filter))
    #expect(list.chips.map(\.count) == before.chips.map(\.count))
    #expect(!desk.context.hasChanges)
    #expect(try entries(desk.context).count == entryCount)
    #expect(try TimerEngine(context: desk.context).settle(at: HookLine.start) == status)
}
