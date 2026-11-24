@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// The presets the app comes with, and a block's own copy of its preset's rhythm.

/// Every preset in `context`, by name.
private func presets(_ context: ModelContext) throws -> [FocusPreset] {
    try context.fetch(FetchDescriptor<FocusPreset>(sortBy: [SortDescriptor(\.name)]))
}

// MARK: - Seeding

@Test func `seeding adds exactly 25/5 and 50/10 with their fixed ids, both resuming by themselves`() throws {
    let context = try ModelContext(ModelStore.inMemory())

    try FocusPreset.seedDefaults(into: context)

    let seeded = try presets(ModelContext(context.container))
    #expect(seeded.map(\.name) == ["25/5", "50/10"])
    #expect(seeded.map(\.id.uuidString) == [
        "DE2C7E38-B1F4-432D-8CAA-D9E742D8F38F",
        "CDD36B97-80FA-4A0B-A01C-AEC5AA10B7B7",
    ])
    #expect(seeded.map(\.focusMinutes) == [25, 50])
    #expect(seeded.map(\.breakMinutes) == [5, 10])
    #expect(seeded.map(\.longBreakMinutes) == [15, 0])
    #expect(seeded.map(\.roundsBeforeLongBreak) == [4, 0])
    #expect(seeded.map(\.resumesAfterBreak) == [true, true])
}

@Test func `seeding again adds nothing`() throws {
    let container = try ModelStore.inMemory()
    try FocusPreset.seedDefaults(into: ModelContext(container))

    try FocusPreset.seedDefaults(into: ModelContext(container))
    try FocusPreset.seedDefaults(into: ModelContext(container))

    #expect(try presets(ModelContext(container)).count == 2)
}

@Test func `seeding gives no workspace a preset, so every workspace stays at none`() throws {
    let desk = try Desk()

    try FocusPreset.seedDefaults(into: desk.context)

    #expect([desk.acme, desk.globex, desk.personal].allSatisfy { $0.focusPreset == nil })
    #expect(try presets(desk.context).allSatisfy { ($0.workspaces ?? []).isEmpty })
}

@Test func `the sample data holds the two presets the app comes with, and no workspace names one`() throws {
    let context = try ModelContext(ModelStore.inMemory())

    try SampleData.seed(into: context, now: nine)

    #expect(try presets(context).map(\.id) == FocusPreset.seededIDs)
    #expect(try context.fetch(FetchDescriptor<Workspace>()).allSatisfy { $0.focusPreset == nil })
}

// MARK: - The block's own copy

@Test func `a block copies its workspace's preset when it starts`() throws {
    let desk = try Desk()
    let preset = FocusPreset(
        name: "Deep", focusMinutes: 40, breakMinutes: 8, longBreakMinutes: 20, roundsBeforeLongBreak: 3,
        resumesAfterBreak: false,
    )
    try desk.acmeFollows(preset)

    try desk.engine.start(desk.acme, at: nine)

    let block = try #require(try desk.engine.runningBlock())
    #expect(block.focusPreset === preset)
    #expect(rhythmCopy(of: block) == [40, 8, 20, 3])
    #expect(!block.resumesAfterBreak)
}

@Test func `editing a preset never changes the rhythm of a block that already started`() throws {
    let desk = try Desk()
    let preset = try desk.acmeFollowsSeeded("25/5")
    try desk.engine.start(desk.acme, at: nine)
    let before = try desk.engine.rhythm(at: at(10))

    preset.focusMinutes = 50
    preset.breakMinutes = 10
    preset.resumesAfterBreak = false
    try desk.context.save()

    #expect(try desk.engine.rhythm(at: at(10)) == before)
    #expect(before?.current == focus(0, 25))
    try desk.engine.startBreak(minutes: 5, at: at(25))
    #expect(try desk.engine.settle(at: at(31)).state == .working)
}

@Test func `deleting a preset unlinks its workspace and blocks, and the running block keeps its rhythm`() throws {
    let desk = try Desk()
    let preset = try desk.acmeFollowsSeeded("25/5")
    try desk.engine.start(desk.acme, at: nine)
    let before = try desk.engine.rhythm(at: at(10))

    desk.context.delete(preset)
    try desk.context.save()

    #expect(desk.acme.focusPreset == nil)
    let block = try #require(try desk.engine.runningBlock())
    #expect(block.focusPreset == nil)
    #expect(try desk.engine.rhythm(at: at(10)) == before)
    #expect(try presets(desk.context).map(\.name) == ["50/10"])

    try desk.engine.start(desk.acme, at: at(20))
    #expect(try desk.engine.rhythm(at: at(20)) == nil)
}
