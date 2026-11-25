@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// Card #58: the list of presets in Settings, its numbers, what keeps a preset
// from being removed, and what survives a restart.

/// The names of every preset in `context`, in the order the list shows them.
private func listed(_ context: ModelContext) throws -> [String] {
    try PresetRoster(context: context).presets().map(\.name)
}

/// The focus, short break and long break minutes of `preset`, and the rounds before the long one.
private func numbers(_ preset: FocusPreset) -> [Int] {
    [preset.focusMinutes, preset.breakMinutes, preset.longBreakMinutes, preset.roundsBeforeLongBreak]
}

// MARK: - The list

@Test func `presets are listed by focus minutes, then break minutes, then name`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    for (name, focus, rest) in [("D", 50, 10), ("B", 25, 5), ("C", 25, 10), ("A", 25, 5), ("E", 15, 60)] {
        context.insert(FocusPreset(name: name, focusMinutes: focus, breakMinutes: rest))
    }
    try context.save()

    #expect(try listed(context) == ["E", "A", "B", "C", "D"])
}

@Test func `an empty store lists no preset`() throws {
    #expect(try listed(ModelContext(ModelStore.inMemory())).isEmpty)
}

// MARK: - Creating

@Test func `a new preset is 25 and 5 with no long break, resumes by itself, and is saved`() throws {
    let container = try ModelStore.inMemory()
    let created = try PresetRoster(context: ModelContext(container)).create(baseName: "New preset")

    let saved = try #require(try PresetRoster(context: ModelContext(container)).presets().first)
    #expect(saved.id == created.id)
    #expect(saved.name == "New preset")
    #expect(numbers(saved) == [25, 5, 0, 0])
    #expect(!saved.hasLongBreak)
    #expect(saved.resumesAfterBreak)
}

@Test func `new presets with a taken name get the next number, and a free one is used again`() throws {
    let roster = try PresetRoster(context: ModelContext(ModelStore.inMemory()))
    let names = try (0 ..< 3).map { _ in try roster.create(baseName: "New preset").name }
    #expect(names == ["New preset", "New preset 2", "New preset 3"])

    let second = try #require(try roster.presets().first { $0.name == "New preset 2" })
    try roster.remove(second)
    #expect(try roster.create(baseName: "New preset").name == "New preset 2")
}

// MARK: - Removing

@Test func `a preset no workspace names is removed for good`() throws {
    let desk = try Desk()
    try FocusPreset.seedDefaults(into: desk.context)
    let roster = PresetRoster(context: desk.context)

    try roster.remove(#require(try roster.presets().first { $0.name == "50/10" }))

    #expect(try listed(ModelContext(desk.container)) == ["25/5"])
}

@Test func `a preset a workspace names is not removed, and nothing changes`() throws {
    let desk = try Desk()
    let preset = try desk.acmeFollowsSeeded("25/5")
    let roster = PresetRoster(context: desk.context)

    #expect(throws: PresetRosterError.inUse) { try roster.remove(preset) }

    #expect(try listed(ModelContext(desk.container)) == ["25/5", "50/10"])
    #expect(desk.acme.focusPreset === preset)
}

@Test func `an archived workspace keeps its preset from being removed too`() throws {
    let desk = try Desk()
    let preset = try desk.acmeFollowsSeeded("25/5")
    try WorkspaceRoster(context: desk.context).archive(desk.acme)
    let roster = PresetRoster(context: desk.context)

    #expect(throws: PresetRosterError.inUse) { try roster.remove(preset) }
    #expect(try listed(ModelContext(desk.container)) == ["25/5", "50/10"])
}

@Test func `once no workspace names it a preset is removed`() throws {
    let desk = try Desk()
    let preset = try desk.acmeFollowsSeeded("25/5")
    desk.acme.focusPreset = nil

    try PresetRoster(context: desk.context).remove(preset)

    #expect(try listed(ModelContext(desk.container)) == ["50/10"])
}

@Test func `the workspaces naming a preset are listed in their order, archived ones included`() throws {
    let desk = try Desk()
    let preset = try desk.acmeFollowsSeeded("25/5")
    desk.personal.focusPreset = preset
    try WorkspaceRoster(context: desk.context).archive(desk.personal)
    let all = [desk.acme, desk.globex, desk.personal]

    #expect(PresetRoster.workspaces(naming: preset, among: all).map(\.name) == ["Acme", "Personal"])
    #expect(PresetRoster.workspaces(naming: preset, among: []).isEmpty)
    let other = try #require(try PresetRoster(context: desk.context).presets().first { $0.name == "50/10" })
    #expect(PresetRoster.workspaces(naming: other, among: all).isEmpty)
}

@Test func `a running block keeps its rhythm when its preset is removed`() throws {
    let desk = try Desk()
    try FocusPreset.seedDefaults(into: desk.context)
    let roster = PresetRoster(context: desk.context)
    let preset = try #require(try roster.presets().first { $0.name == "25/5" })
    try desk.engine.start(desk.acme, minutes: 120, rhythm: .preset(preset), at: nine)
    let before = try checkedRhythm(desk.engine, at: at(10))

    try roster.remove(preset)

    #expect(try checkedRhythm(desk.engine, at: at(10)) == before)
    #expect(try desk.engine.runningBlock()?.focusPreset == nil)
}

// MARK: - Numbers

@Test(arguments: [
    (-5, 1), (0, 1), (1, 1), (25, 25), (240, 240), (241, 240), (100_000, 240), (Int.max, 240), (Int.min, 1),
] as [(Int, Int)])
func `edited minutes are brought into 1 to 240`(edited: Int, kept: Int) {
    #expect(PresetRoster.number(edited, replacing: 30, in: PresetRoster.minuteRange) == kept)
}

@Test(arguments: [(0, 2), (1, 2), (2, 2), (4, 4), (12, 12), (13, 12)] as [(Int, Int)])
func `edited rounds are brought into 2 to 12`(edited: Int, kept: Int) {
    #expect(PresetRoster.number(edited, replacing: 6, in: PresetRoster.roundRange) == kept)
}

@Test(arguments: [-3, 0, 500])
func `a stored number outside the range stays until it is edited to another one`(stored: Int) {
    #expect(PresetRoster.number(stored, replacing: stored, in: PresetRoster.minuteRange) == stored)
    let other = PresetRoster.number(stored + 1, replacing: stored, in: PresetRoster.minuteRange)
    #expect(PresetRoster.minuteRange.contains(other))
}

@Test(arguments: [(25, 26), (239, 240), (240, 240), (500, 240), (-3, 2), (1, 2)] as [(Int, Int)])
func `a step up moves by one inside the range, whatever is stored`(stored: Int, kept: Int) {
    #expect(PresetRoster.number(stored, steppedBy: 1, in: PresetRoster.minuteRange) == kept)
}

@Test(arguments: [(25, 24), (2, 1), (1, 1), (500, 239), (-3, 1), (240, 239)] as [(Int, Int)])
func `a step down moves by one inside the range, whatever is stored`(stored: Int, kept: Int) {
    #expect(PresetRoster.number(stored, steppedBy: -1, in: PresetRoster.minuteRange) == kept)
}

// MARK: - The long break

@Test func `a long break switched on starts at 15 minutes after 4 rounds, and switched off stores zeros`() {
    let preset = FocusPreset(name: "P", focusMinutes: 25, breakMinutes: 5)
    #expect(!preset.hasLongBreak)

    preset.hasLongBreak = true
    #expect(numbers(preset) == [25, 5, 15, 4])

    preset.hasLongBreak = false
    #expect(numbers(preset) == [25, 5, 0, 0])
}

@Test func `setting the long break to what it already is changes nothing`() {
    let full = FocusPreset(
        name: "Full", focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 30, roundsBeforeLongBreak: 2,
    )
    full.hasLongBreak = true
    #expect(numbers(full) == [25, 5, 30, 2])

    // Minutes without rounds are no long break, and stay as stored until it is switched on.
    let half = FocusPreset(name: "Half", focusMinutes: 25, breakMinutes: 5, longBreakMinutes: 20)
    half.hasLongBreak = false
    #expect(numbers(half) == [25, 5, 20, 0])
    half.hasLongBreak = true
    #expect(numbers(half) == [25, 5, 15, 4])
}

// MARK: - The rhythm of a block

@Test func `the rhythm of a preset is that preset, and none for no id or one that is gone`() throws {
    let desk = try Desk()
    try FocusPreset.seedDefaults(into: desk.context)
    let roster = PresetRoster(context: desk.context)
    let preset = try #require(try roster.presets().first)

    #expect(try roster.rhythm(ofPreset: preset.id) == .preset(preset))
    #expect(try roster.rhythm(ofPreset: nil) == BlockRhythm.none)
    let gone = preset.id
    try roster.remove(preset)
    #expect(try roster.rhythm(ofPreset: gone) == BlockRhythm.none)
    #expect(try roster.rhythm(ofPreset: UUID()) == BlockRhythm.none)
}

@Test func `a block follows its workspace's default, none, or the preset it was given`() throws {
    let desk = try Desk()
    try desk.acmeFollowsSeeded("25/5")
    let other = try #require(try PresetRoster(context: desk.context).presets().first { $0.name == "50/10" })

    try desk.engine.start(desk.acme, minutes: 120, at: nine)
    #expect(try rhythmCopy(of: #require(try desk.engine.runningBlock())) == [25, 5, 15, 4])

    try desk.engine.start(desk.acme, minutes: 120, rhythm: .none, at: at(1))
    #expect(try rhythmCopy(of: #require(try desk.engine.runningBlock())) == [0, 0, 0, 0])
    #expect(try desk.engine.runningBlock()?.focusPreset == nil)

    try desk.engine.start(desk.acme, minutes: 120, rhythm: .preset(other), at: at(2))
    #expect(try rhythmCopy(of: #require(try desk.engine.runningBlock())) == [50, 10, 0, 0])
    #expect(try desk.engine.runningBlock()?.focusPreset === other)

    #expect(desk.acme.focusPreset?.name == "25/5")
}

@Test func `a preset given to a block of a workspace without one leaves that workspace without one`() throws {
    let desk = try Desk()
    try FocusPreset.seedDefaults(into: desk.context)
    let preset = try #require(try PresetRoster(context: desk.context).presets().first)

    try desk.engine.start(desk.globex, minutes: 60, rhythm: .preset(preset), at: nine)

    #expect(desk.globex.focusPreset == nil)
    #expect(try checkedRhythm(desk.engine, at: nine).current == focus(0, 25))
}

// MARK: - Seeding once

@Test func `seeding is remembered, so presets that were all removed stay removed`() throws {
    let container = try ModelStore.inMemory()
    var isSeeded = false
    try FocusPreset.seedDefaults(into: ModelContext(container), isSeeded: &isSeeded)
    #expect(isSeeded)
    let roster = PresetRoster(context: ModelContext(container))
    for preset in try roster.presets() {
        try roster.remove(preset)
    }

    try FocusPreset.seedDefaults(into: ModelContext(container), isSeeded: &isSeeded)

    #expect(try listed(ModelContext(container)).isEmpty)
    #expect(isSeeded)
}

@Test func `a store that already has presets counts as seeded and gets none added`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    try PresetRoster(context: context).create(baseName: "Mine")
    var isSeeded = false

    try FocusPreset.seedDefaults(into: context, isSeeded: &isSeeded)

    #expect(isSeeded)
    #expect(try listed(context) == ["Mine"])
}

// MARK: - Across a restart

@Test func `a workspace's default rhythm survives a restart`() throws {
    try withTemporaryFolder { folder in
        do {
            let context = try ModelContext(ModelStore.onDisk(in: folder.url))
            var isSeeded = false
            try FocusPreset.seedDefaults(into: context, isSeeded: &isSeeded)
            let acme = Workspace(name: "Acme", color: .teal)
            context.insert(acme)
            context.insert(Workspace(name: "Globex", color: .indigo, sortOrder: 1))
            acme.focusPreset = try PresetRoster(context: context).presets().first { $0.name == "50/10" }
            try context.save()
        }

        let context = try ModelContext(ModelStore.onDisk(in: folder.url))
        let workspaces = try context.fetch(FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(workspaces.map { $0.focusPreset?.name } == ["50/10", nil])
        let engine = TimerEngine(context: context)
        try engine.start(#require(workspaces.first), minutes: 120, at: nine)
        #expect(try checkedRhythm(engine, at: nine).current == focus(0, 50))
    }
}

@Test func `a created and changed preset is the same after a restart, and removed ones stay removed`() throws {
    try withTemporaryFolder { folder in
        var isSeeded = false
        do {
            let context = try ModelContext(ModelStore.onDisk(in: folder.url))
            try FocusPreset.seedDefaults(into: context, isSeeded: &isSeeded)
            let roster = PresetRoster(context: context)
            for preset in try roster.presets() {
                try roster.remove(preset)
            }
            let created = try roster.create(baseName: "New preset")
            created.name = "Short"
            created.focusMinutes = 15
            created.hasLongBreak = true
            created.resumesAfterBreak = false
            try context.save()
        }

        let context = try ModelContext(ModelStore.onDisk(in: folder.url))
        try FocusPreset.seedDefaults(into: context, isSeeded: &isSeeded)

        let preset = try #require(try PresetRoster(context: context).presets().first)
        #expect(try listed(context) == ["Short"])
        #expect(numbers(preset) == [15, 5, 15, 4])
        #expect(!preset.resumesAfterBreak)
    }
}

@Test func `with every preset removed none comes back after a restart`() throws {
    try withTemporaryFolder { folder in
        var isSeeded = false
        do {
            let context = try ModelContext(ModelStore.onDisk(in: folder.url))
            try FocusPreset.seedDefaults(into: context, isSeeded: &isSeeded)
            let roster = PresetRoster(context: context)
            for preset in try roster.presets() {
                try roster.remove(preset)
            }
        }

        let context = try ModelContext(ModelStore.onDisk(in: folder.url))
        try FocusPreset.seedDefaults(into: context, isSeeded: &isSeeded)

        #expect(try listed(context).isEmpty)
    }
}
