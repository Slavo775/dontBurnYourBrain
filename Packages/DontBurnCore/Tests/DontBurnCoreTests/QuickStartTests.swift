@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// 2026-01-15 08:41:30 UTC, the sample data's now.
private let sampleNow = Date(timeIntervalSince1970: 1_768_466_490)

/// An in-memory store with the sample set: Acme, Globex and Personal.
private func sampleRoster() throws -> WorkspaceRoster {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: sampleNow)
    return WorkspaceRoster(context: context)
}

/// The name of the active workspace on quick start `key`, as the panel picks it.
private func workspace(onKey key: Int, in roster: WorkspaceRoster) throws -> String? {
    let active = try roster.activeWorkspaces()
    guard let position = WorkspaceRoster.quickStartPosition(ofKey: key), active.indices.contains(position) else {
        return nil
    }
    return active[position].name
}

// MARK: - Keys

@Test func `keys 1 to 9 pick the first nine positions`() {
    #expect((1 ... 9).map(WorkspaceRoster.quickStartPosition(ofKey:)) == Array(0 ... 8))
}

@Test(arguments: [0, 10, -1, 99, Int.max, Int.min])
func `a key outside 1 to 9 picks no position`(key: Int) {
    #expect(WorkspaceRoster.quickStartPosition(ofKey: key) == nil)
}

@Test func `a row's shown key picks that same row`() {
    for position in 0 ..< WorkspaceRoster.quickStartKeyCount {
        let key = WorkspaceRoster.quickStartKey(at: position)
        #expect(key.flatMap(WorkspaceRoster.quickStartPosition(ofKey:)) == position)
    }
}

// MARK: - What is offered

@Test func `the sample workspaces are offered in their order on keys 1 to 3`() throws {
    let roster = try sampleRoster()
    #expect(try (1 ... 4).map { try workspace(onKey: $0, in: roster) } == ["Acme", "Globex", "Personal", nil])
}

@Test func `an archived workspace is not offered and the ones after it move up a key`() throws {
    let roster = try sampleRoster()
    try roster.archive(roster.activeWorkspaces()[1])

    #expect(try workspace(onKey: 1, in: roster) == "Acme")
    #expect(try workspace(onKey: 2, in: roster) == "Personal")
    #expect(try workspace(onKey: 3, in: roster) == nil)
}

@Test func `reordering in Settings changes which workspace a key starts`() throws {
    let roster = try sampleRoster()
    try roster.move(fromOffsets: [2], toOffset: 0)

    #expect(try (1 ... 3).map { try workspace(onKey: $0, in: roster) } == ["Personal", "Acme", "Globex"])
}

@Test func `with every workspace archived nothing is offered`() throws {
    let roster = try sampleRoster()
    for active in try roster.activeWorkspaces() {
        try roster.archive(active)
    }

    #expect(try roster.activeWorkspaces().isEmpty)
    #expect(try workspace(onKey: 1, in: roster) == nil)
}

@Test func `with more than nine workspaces the first nine get keys and the rest none`() throws {
    let roster = try WorkspaceRoster(context: ModelContext(ModelStore.inMemory()))
    for _ in 0 ..< 11 {
        try roster.create(baseName: "Acme")
    }
    let active = try roster.activeWorkspaces()

    #expect(active.count == 11)
    #expect(active.indices.map(WorkspaceRoster.quickStartKey(at:)) == Array(1 ... 9) + [nil, nil])
    #expect(try workspace(onKey: 9, in: roster) == "Acme 9")
}

// MARK: - The menu

@Test func `the menu offers the first three active workspaces`() throws {
    let roster = try WorkspaceRoster(context: ModelContext(ModelStore.inMemory()))
    for _ in 0 ..< 5 {
        try roster.create(baseName: "Acme")
    }
    try roster.archive(roster.activeWorkspaces()[1])

    let offered = try roster.activeWorkspaces().prefix(WorkspaceRoster.menuStartCount).map(\.name)
    #expect(WorkspaceRoster.menuStartCount == 3)
    #expect(offered == ["Acme", "Acme 3", "Acme 4"])
}

// MARK: - Starting

@Test func `a quick start uses the workspace's default length`() throws {
    let desk = try Desk()
    try desk.engine.start(desk.globex, at: nine)

    #expect(try desk.engine.runningBlock()?.plannedMinutes == 45)
    #expect(try desk.engine.runningBlock()?.workspace === desk.globex)
}

@Test(arguments: [false, true])
func `a custom block over a paused block or a break ends it and keeps the chosen length`(onBreak: Bool) throws {
    let desk = try Desk()
    try desk.engine.start(desk.acme, at: nine)
    if onBreak {
        try desk.engine.startBreak(at: at(10))
    } else {
        try desk.engine.pause(at: at(10))
    }

    try desk.engine.start(desk.personal, minutes: 120, at: at(15))

    let all = try blocks(desk.context)
    #expect(all.map(\.state) == [.done, .running])
    #expect(all.last?.plannedMinutes == 120)
    #expect(desk.personal.defaultBlockMinutes == 25)
    try expectHistoryKeepsRules(desk.context)
}

// MARK: - The footer

@Test func `today's total reads as hours and minutes, rounded down`() {
    #expect(MenuBarLabel.hoursAndMinutes(0) == "0:00")
    #expect(MenuBarLabel.hoursAndMinutes(599) == "0:09")
    #expect(MenuBarLabel.hoursAndMinutes(600) == "0:10")
    #expect(MenuBarLabel.hoursAndMinutes(10 * 3600 + 5 * 60) == "10:05")
    #expect(MenuBarLabel.hoursAndMinutes(-30) == "0:00")
}
