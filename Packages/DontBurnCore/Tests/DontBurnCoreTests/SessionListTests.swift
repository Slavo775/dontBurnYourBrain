@testable import DontBurnCore
import Foundation
import Testing

/// Two sessions in Web shop, one in Mobile app, one in Reading and one in no
/// project's folder. The last workspace's session and the one in no project
/// came first.
private func fiveSessions() throws -> SessionDesk {
    var desk = SessionDesk()
    try desk.send(0, "SessionStart", "scratch", in: "/code/scratch")
    try desk.send(1, "UserPromptSubmit", "reading", in: "/code/reading-notes")
    try desk.send(2, "SessionStart", "web-1", in: "/code/acme-web")
    try desk.send(3, "PermissionRequest", "mobile", in: "/code/acme-mobile")
    try desk.send(4, "SessionStart", "web-2", in: "/code/acme-web")
    return desk
}

// MARK: - The chips

@Test(arguments: [SessionFilter.all, .other, .workspace(UUID())])
func `with no session there is no chip and no group, and the filter is All`(filter: SessionFilter) {
    let list = SessionDesk().list(at: 0, filter: filter)

    #expect(list.isEmpty)
    #expect(list.chips.isEmpty)
    #expect(list.sections.isEmpty)
    #expect(list.filter == .all)
}

@Test func `the chips are All, the workspaces with a session in their order, then Other, each with its count`() throws {
    let desk = try fiveSessions()

    #expect(desk.list(at: 10).chips == [
        SessionList.Chip(filter: .all, workspaceName: nil, count: 5),
        SessionList.Chip(filter: .workspace(desk.acme.id), workspaceName: "Acme", count: 3),
        SessionList.Chip(filter: .workspace(desk.personal.id), workspaceName: "Personal", count: 1),
        SessionList.Chip(filter: .other, workspaceName: nil, count: 1),
    ])
}

@Test func `with one workspace there is no Other, and with no project at all there is only All and Other`() throws {
    var desk = SessionDesk()
    try desk.send(0, "SessionStart", "web")
    #expect(desk.list(at: 1).chips.map(\.filter) == [.all, .workspace(desk.acme.id)])

    desk.projects = [:]
    try desk.send(2, "SessionStart", "globex", in: "/code/globex-data")
    let list = desk.list(at: 3)
    #expect(list.chips == [
        SessionList.Chip(filter: .all, workspaceName: nil, count: 2),
        SessionList.Chip(filter: .other, workspaceName: nil, count: 2),
    ])
    #expect(list.rows.map(\.title) == ["globex-data", "acme-web"])
}

@Test func `workspaces at the same place in the order get their chips by name`() throws {
    // Again and again, as the identifiers differ each time and could put them in order by chance.
    for _ in 0 ..< 20 {
        var desk = SessionDesk()
        try desk.send(0, "SessionStart", "reading", in: "/code/reading-notes")
        try desk.send(1, "SessionStart", "globex", in: "/code/globex-data")
        try desk.send(2, "SessionStart", "web")
        desk.globex.sortOrder = desk.acme.sortOrder
        desk.personal.sortOrder = desk.acme.sortOrder
        #expect(desk.list(at: 3).chips.compactMap(\.workspaceName) == ["Acme", "Globex", "Personal"])

        desk.acme.sortOrder = 5
        #expect(desk.list(at: 3).chips.compactMap(\.workspaceName) == ["Globex", "Personal", "Acme"])
    }
}

@Test func `a workspace without a name keeps its chip, with an empty name`() throws {
    var desk = SessionDesk()
    desk.acme.name = ""
    try desk.send(0, "SessionStart", "web")

    #expect(desk.list(at: 1).chips.map(\.workspaceName) == [nil, ""])
}

// MARK: - The filter

@Test func `each chip shows exactly the sessions it counts, and the chips stay the same under it`() throws {
    let desk = try fiveSessions()
    let chips = desk.list(at: 10).chips
    var shown: [SessionFilter: Set<String>] = [:]
    for chip in chips {
        let list = desk.list(at: 10, filter: chip.filter)
        #expect(list.filter == chip.filter)
        #expect(list.chips == chips)
        #expect(list.rows.count == chip.count)
        shown[chip.filter] = Set(list.rows.map(\.id))
    }

    #expect(shown == [
        .all: ["scratch", "reading", "web-1", "mobile", "web-2"],
        .workspace(desk.acme.id): ["web-1", "mobile", "web-2"],
        .workspace(desk.personal.id): ["reading"],
        .other: ["scratch"],
    ])
}

@Test func `a filter whose last session is gone falls back to All`() throws {
    var desk = SessionDesk()
    try desk.send(0, "SessionStart", "web")
    try desk.send(1, "SessionStart", "globex", in: "/code/globex-data")
    try desk.send(2, "SessionStart", "scratch", in: "/code/scratch")
    let globex = SessionFilter.workspace(desk.globex.id)
    #expect(desk.list(at: 3, filter: globex).filter == globex)
    #expect(desk.list(at: 3, filter: .other).filter == .other)

    try desk.send(4, "SessionEnd", "globex", in: "/code/globex-data")
    try desk.send(5, "SessionEnd", "scratch", in: "/code/scratch")
    for filter in [globex, .other, .workspace(UUID())] {
        let list = desk.list(at: 6, filter: filter)
        #expect(list.filter == .all)
        #expect(list.chips.map(\.filter) == [.all, .workspace(desk.acme.id)])
        #expect(list.rows.map(\.id) == ["web"])
    }
}

@Test func `a filter whose sessions lost their project falls back to All, and they go to Other`() throws {
    var desk = SessionDesk()
    try desk.send(0, "SessionStart", "globex", in: "/code/globex-data")
    desk.projects["/code/globex-data"] = nil
    let list = desk.list(at: 1, filter: .workspace(desk.globex.id))

    #expect(list.filter == .all)
    #expect(list.chips.map(\.filter) == [.all, .other])
    #expect(list.rows.map(\.id) == ["globex"])
}

// MARK: - The groups

@Test func `the groups are Needs you, Working and Idle, in this order, and one without a session is left out`() throws {
    var desk = SessionDesk()
    try desk.send(0, "SessionStart", "idle")
    try desk.send(1, "UserPromptSubmit", "working", in: "/code/globex-data")
    try desk.send(2, "PermissionRequest", "waiting", in: "/code/scratch")
    let list = desk.list(at: 3)
    #expect(list.sections.map(\.group) == [.needsYou, .working, .idle])
    #expect(list.sections.map { $0.rows.map(\.id) } == [["waiting"], ["working"], ["idle"]])

    let globex = desk.list(at: 3, filter: .workspace(desk.globex.id))
    #expect(globex.sections.map(\.group) == [.working])
}

@Test func `a session moves between the groups as its events come, and leaves when it ends`() throws {
    var desk = SessionDesk()
    try desk.send(0, "SessionStart", "web")
    #expect(desk.list(at: 0).ids(.idle) == ["web"])
    try desk.send(1, "UserPromptSubmit", "web")
    #expect(desk.list(at: 1).ids(.working) == ["web"])
    try desk.send(2, "PermissionRequest", "web")
    #expect(desk.list(at: 2).ids(.needsYou) == ["web"])
    try desk.send(9, "Notification", "web", ["notification_type": "idle_prompt"])
    #expect(desk.list(at: 9).ids(.idle) == ["web"])
    try desk.send(10, "UserPromptSubmit", "web")
    #expect(desk.list(at: 10).sections.map(\.group) == [.working])

    // Ended, and nothing has pruned it yet.
    try desk.send(11, "SessionEnd", "web")
    #expect(desk.replay.store.sessions.map(\.id) == ["web"])
    #expect(desk.list(at: 11).isEmpty)
}

@Test func `a stopped turn moves from Working to Idle after the finish delay, with no event in between`() throws {
    var desk = SessionDesk()
    try desk.send(0, "UserPromptSubmit", "web")
    try desk.send(10, "Stop", "web", HookLine.tasks())
    let end = 10 + AgentSession.finishDelay

    for moment in [10, end - 0.01] {
        #expect(desk.list(at: moment).sections.map(\.group) == [.working])
        #expect(desk.list(at: moment).rows.map(\.idleMinutes) == [nil])
    }
    #expect(desk.list(at: end).sections.map(\.group) == [.idle])
    #expect(desk.list(at: end).rows.map(\.idleMinutes) == [0])
    // Counted from the Stop, not from the end of the delay.
    #expect(desk.list(at: 10 + 60).rows.map(\.idleMinutes) == [1])
}

// MARK: - The order inside a group

@Test(arguments: [
    ("PermissionRequest", SessionGroup.needsYou, ["a", "b", "c"]),
    ("UserPromptSubmit", .working, ["a", "b", "c"]),
    ("SessionStart", .idle, ["a", "c", "b"]),
])
func `the oldest session comes first in Needs you and Working, and the last active one in Idle`(
    name: String, group: SessionGroup, expected: [String],
) throws {
    var desk = SessionDesk()
    for id in ["a", "b", "c"] {
        try desk.send(0, "SessionStart", id)
    }
    try desk.send(10, name, "b")
    try desk.send(20, name, "c")
    try desk.send(30, name, "a")

    #expect(desk.list(at: 40).sections.map(\.group) == [group])
    #expect(desk.list(at: 40).ids(group) == expected)
}

@Test(arguments: [
    ("PermissionRequest", SessionGroup.needsYou), ("UserPromptSubmit", .working), ("SessionStart", .idle),
])
func `sessions whose events came at the same moment keep the order they started in`(
    name: String, group: SessionGroup,
) throws {
    var desk = SessionDesk()
    let ids = (0 ..< 40).map { "session-\($0)" }
    for id in ids {
        try desk.send(0, "SessionStart", id)
    }
    for id in ids.reversed() {
        try desk.send(10, name, id)
    }

    #expect(desk.list(at: 20).ids(group) == ids)
}

@Test func `a row in Working keeps its place as events come in`() throws {
    var desk = SessionDesk()
    for id in ["a", "b", "c"] {
        try desk.send(0, "UserPromptSubmit", id)
    }
    try desk.send(10, "SubagentStart", "b", HookLine.subagent("Explore"))
    #expect(desk.list(at: 10).ids(.working) == ["a", "b", "c"])
    try desk.send(20, "UserPromptSubmit", "a")
    #expect(desk.list(at: 20).ids(.working) == ["a", "b", "c"])
    try desk.send(30, "Stop", "c", HookLine.tasks())
    #expect(desk.list(at: 30).ids(.working) == ["a", "b", "c"])
}

@Test func `a row in Needs you keeps its place through the reminder of its request and a subagent's events`() throws {
    var desk = SessionDesk()
    try desk.send(0, "PermissionRequest", "a")
    try desk.send(3, "PermissionRequest", "b")
    #expect(desk.list(at: 4).ids(.needsYou) == ["a", "b"])
    // Claude Code's reminder of each request, about six seconds later.
    try desk.send(6, "Notification", "a", ["notification_type": "permission_prompt"])
    #expect(desk.list(at: 7).ids(.needsYou) == ["a", "b"])
    try desk.send(9, "Notification", "b", ["notification_type": "permission_prompt"])
    #expect(desk.list(at: 10).ids(.needsYou) == ["a", "b"])
    try desk.send(100, "SubagentStop", "a", HookLine.subagent("Explore"))
    #expect(desk.list(at: 101).ids(.needsYou) == ["a", "b"])
    #expect(desk.list(at: 5000).ids(.needsYou) == ["a", "b"])
}
