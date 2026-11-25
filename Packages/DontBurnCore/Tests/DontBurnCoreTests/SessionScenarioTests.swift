@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

private let now = Date(timeIntervalSince1970: 1_768_466_490)
private let root = URL(filePath: "/sample", directoryHint: .isDirectory)

/// The list the app shows with `scenario`: the sample set in memory, its
/// folders and the scenario's below `root`, and its sessions at `now`.
private func sampleList(_ scenario: SessionScenario, root: URL) throws -> SessionList {
    let synced = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: synced, now: now)
    let local = try ModelContext(ModelStore.localInMemory())
    for folders in [SampleData.folders, scenario.folders] {
        try SampleData.seedFolders(folders, into: local, projects: synced, root: root)
    }
    let projects = try synced.fetch(FetchDescriptor<Project>())
    let holders = ProjectFolders(context: local)
    return try SessionList(sessions: scenario.store(root: root, now: now).sessions, at: now) {
        try $0.project(in: holders, among: projects)
    }
}

// MARK: - The launch argument

@Test(arguments: [("list", SessionScenario.list), ("many", .many), ("none", .empty), ("no-hook", .noHook)])
func `a session scenario is named by its exact value`(raw: String, scenario: SessionScenario) {
    #expect(SessionScenario(launchArgument: raw) == scenario)
    #expect(scenario.rawValue == raw)
}

@Test(arguments: [
    nil, "", "MANY", "None", "No-Hook", "nohook", "no_hook", "noHook", "empty", " many", "many ", "many\n",
    "no-hook\u{0}", "no\u{2011}hook", "YES", "0", "no-hook-no-hook-no", String(repeating: "many", count: 10000),
])
func `without the argument, or with any other value, the session scenario is the list`(raw: String?) {
    #expect(SessionScenario(launchArgument: raw) == .list)
}

// MARK: - The sample list

@Test func `the sample list has every group, every sample workspace, Other and an untracked project`() throws {
    try withTemporaryFolder { temporary in
        let list = try sampleList(.list, root: temporary.url)

        #expect(list.chips.map(\.workspaceName) == [nil, "Acme", "Globex", "Personal", nil])
        #expect(list.chips.map(\.count) == [6, 2, 1, 2, 1])
        #expect(list.chips.first?.filter == .all)
        #expect(list.chips.last?.filter == .other)
        #expect(list.sections.map(\.group) == [.needsYou, .working, .idle])
        #expect(list.sections.map { $0.rows.map(\.title) } == [
            ["Web shop"], ["Mobile app", "Data platform"], ["Side project", "Reading", "scratch"],
        ])
        #expect(list.rows.map(\.color) == [.teal, .teal, .indigo, .ochre, .ochre, nil])
        #expect(list.rows.map(\.profile) == ["acme", "acme", "globex", "personal", "personal", nil])
        #expect(list.rows.map(\.terminal) == [.iTerm2, .cursor, .visualStudioCode, .terminal, .iTerm2, nil])
        #expect(list.rows.map(\.idleMinutes) == [nil, nil, nil, 12, 40, 185])
    }
}

@Test func `the many sessions are the list five times over and one in a folder with a long name`() throws {
    try withTemporaryFolder { temporary in
        let list = try sampleList(.many, root: temporary.url)

        #expect(list.chips.map(\.workspaceName) == [nil, "Acme", "Globex", "Personal", nil])
        #expect(list.chips.map(\.count) == [31, 10, 5, 10, 6])
        #expect(list.sections.map(\.rows.count) == [5, 11, 15])
        #expect(Set(list.rows.map(\.id)).count == 31)
        let long = try #require(list.rows.max { $0.title.count < $1.title.count })
        #expect(long.title.count > 80)
        #expect((long.profile ?? "").count > 30)
        #expect(long.color == nil)
    }
}

@Test(arguments: [(SessionScenario.empty, NoSessions.noneRunning), (.noHook, .hookNotInstalled)])
func `the scenarios without sessions are empty, each for its own reason`(
    scenario: SessionScenario, reason: NoSessions,
) throws {
    #expect(try scenario.store(root: root, now: now).sessions.isEmpty)
    #expect(scenario.folders.isEmpty)
    #expect(NoSessions(hooks: scenario.hooks) == reason)
}

@Test(arguments: [SessionScenario.list, .many])
func `a scenario with sessions has the hook installed`(scenario: SessionScenario) {
    #expect(NoSessions(hooks: scenario.hooks) == .noneRunning)
}

@Test(arguments: SessionScenario.allCases)
func `the sample sessions follow the time they are given`(scenario: SessionScenario) throws {
    let later = now.addingTimeInterval(90061.5)
    let first = try SessionList(sessions: scenario.store(root: root, now: now).sessions, at: now) { _ in nil }
    let second = try SessionList(sessions: scenario.store(root: root, now: later).sessions, at: later) { _ in nil }

    #expect(first == second)
}

// MARK: - What the sample sessions name

@Test(arguments: SessionScenario.allCases)
func `the sample sessions lie below the root, and name no real process, tab or profile`(
    scenario: SessionScenario,
) throws {
    let sessions = try scenario.store(root: root, now: now).sessions

    for session in sessions {
        #expect(session.folder.hasPrefix("/sample/code/"))
        #expect(session.profile?.hasPrefix("/sample/.claude-") ?? true)
        // macOS gives out process IDs up to 99,999.
        #expect(session.processID > 99999)
        #expect(session.tty == nil)
        #expect(session.tabID == nil)
        #expect(session.lastActivity <= now)
    }
    #expect(Set(sessions.map(\.processID)).count == sessions.count)
    #expect(Set(sessions.map(\.id)).count == sessions.count)
}

@Test(arguments: SessionScenario.allCases)
func `the sample sessions use only the sample names`(scenario: SessionScenario) throws {
    let folders: Set = [
        "acme-web", "acme-mobile", "globex-data", "reading-notes", "side-project", "scratch",
        "a-scratch-folder-with-a-name-far-too-long-to-fit-into-one-row-of-the-session-list",
    ]
    let profiles: Set = ["acme", "globex", "personal", "a-profile-with-a-long-name-of-its-own"]
    let sessions = try scenario.store(root: root, now: now).sessions
    let list = SessionList(sessions: sessions, at: now) { _ in nil }

    #expect(Set(list.rows.map(\.title)).isSubset(of: folders))
    #expect(Set(list.rows.compactMap(\.profile)).isSubset(of: profiles))
}

@Test func `making the sample sessions makes nothing on disk`() throws {
    try withTemporaryFolder { temporary in
        for scenario in SessionScenario.allCases {
            _ = try scenario.store(root: temporary.url, now: now)
        }

        #expect(try FileManager.default.contentsOfDirectory(atPath: temporary.path).isEmpty)
    }
}
