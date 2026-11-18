@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// 2026-01-15 08:41:30 UTC, the sample data's now.
private let sampleNow = Date(timeIntervalSince1970: 1_768_466_490)

/// An in-memory store with the sample set: Acme, Globex and Personal with their history.
private func sampleContext() throws -> ModelContext {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: sampleNow)
    return context
}

private func everyWorkspace(_ context: ModelContext) throws -> [Workspace] {
    try context.fetch(FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.name)]))
}

private func names(_ roster: WorkspaceRoster) throws -> [String] {
    try roster.activeWorkspaces().map(\.name)
}

private func sortOrders(_ roster: WorkspaceRoster) throws -> [Int] {
    try roster.activeWorkspaces().map(\.sortOrder)
}

// MARK: - Names

@Test func `a new name is the base when nothing takes it`() {
    #expect(WorkspaceRoster.uniqueName(base: "New workspace", taken: []) == "New workspace")
    #expect(WorkspaceRoster.uniqueName(base: "New workspace", taken: ["Acme", "New workspace 2"]) == "New workspace")
}

@Test func `a taken name gets the lowest free number from 2`() {
    let base = "New workspace"
    #expect(WorkspaceRoster.uniqueName(base: base, taken: [base]) == "New workspace 2")
    #expect(WorkspaceRoster.uniqueName(base: base, taken: [base, "\(base) 2", "\(base) 3"]) == "New workspace 4")
    #expect(WorkspaceRoster.uniqueName(base: base, taken: [base, "\(base) 3"]) == "New workspace 2")
}

@Test func `new workspaces are numbered and an archived name counts as taken`() throws {
    let roster = try WorkspaceRoster(context: ModelContext(ModelStore.inMemory()))
    let first = try roster.create(baseName: "New workspace")
    try roster.archive(first)
    let second = try roster.create(baseName: "New workspace")
    let third = try roster.create(baseName: "New workspace")

    #expect(first.name == "New workspace")
    #expect(second.name == "New workspace 2")
    #expect(third.name == "New workspace 3")
}

@Test func `two workspaces may share a name and stay apart`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)
    let active = try roster.activeWorkspaces()
    active[1].name = "Acme"
    try context.save()

    try roster.move(fromOffsets: [0], toOffset: 3)
    try roster.archive(active[0])
    try roster.restore(active[0])

    let reread = try roster.activeWorkspaces()
    #expect(reread.map(\.name) == ["Acme", "Personal", "Acme"])
    #expect(reread.map(\.id) == [active[1].id, active[2].id, active[0].id])
    #expect(Set(reread.map(\.id)).count == 3)
    #expect(try sortOrders(roster) == [0, 1, 2])
    #expect(active[0].entries?.count == 4)
    #expect(active[1].entries?.count == 1)
    #expect(try roster.create(baseName: "Acme").name == "Acme 2")
}

@Test func `an empty name is kept as it is`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)
    let acme = try #require(roster.activeWorkspaces().first)
    acme.name = ""
    try context.save()

    #expect(try names(WorkspaceRoster(context: ModelContext(context.container))) == ["", "Globex", "Personal"])
}

// MARK: - Colors

@Test func `the first unused color follows the palette order`() {
    #expect(WorkspaceRoster.firstUnusedColor(used: []) == .teal)
    #expect(WorkspaceRoster.firstUnusedColor(used: [.teal, .indigo, .ochre]) == .orange)
    #expect(WorkspaceRoster.firstUnusedColor(used: [.teal, .orange, .indigo, .raspberry, .ochre]) == .slate)
    #expect(WorkspaceRoster.firstUnusedColor(used: [.orange, .orange]) == .teal)
}

@Test func `with all six colors used a new workspace gets teal`() {
    #expect(WorkspaceRoster.firstUnusedColor(used: WorkspaceColor.allCases) == .teal)
    #expect(WorkspaceRoster.firstUnusedColor(used: WorkspaceColor.allCases.reversed() + [.slate]) == .teal)
}

@Test func `a new workspace skips colors in use and ignores archived ones`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)
    let globex = try roster.activeWorkspaces()[1]

    #expect(try roster.create(baseName: "New workspace").color == .orange)
    try roster.archive(globex)
    #expect(try roster.create(baseName: "New workspace").color == .indigo)
    #expect(try roster.create(baseName: "New workspace").color == .raspberry)
    #expect(try roster.create(baseName: "New workspace").color == .slate)
    #expect(try roster.create(baseName: "New workspace").color == .teal)
}

// MARK: - A new workspace

@Test func `a new workspace goes last with a one hour block`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)
    let created = try roster.create(baseName: "New workspace")

    #expect(try names(roster) == ["Acme", "Globex", "Personal", "New workspace"])
    #expect(try sortOrders(roster) == [0, 1, 2, 3])
    #expect(created.defaultBlockMinutes == 60)
    #expect(WorkspaceRoster.defaultBlockMinutes == 60)
    #expect(!created.isArchived)
    #expect(!context.hasChanges)
}

@Test func `the first workspace in an empty store gets key 1, teal and the plain name`() throws {
    let roster = try WorkspaceRoster(context: ModelContext(ModelStore.inMemory()))
    #expect(try roster.activeWorkspaces().isEmpty)

    let created = try roster.create(baseName: "New workspace")

    #expect(created.name == "New workspace")
    #expect(created.color == .teal)
    #expect(created.sortOrder == 0)
}

// MARK: - Quick start keys

@Test func `the first nine positions get keys 1 to 9`() {
    #expect((0 ..< 9).map(WorkspaceRoster.quickStartKey(at:)) == Array(1 ... 9))
}

@Test(arguments: [-1, 9, 10, Int.max, Int.min])
func `a position outside the first nine gets no key`(position: Int) {
    #expect(WorkspaceRoster.quickStartKey(at: position) == nil)
}

// MARK: - Block lengths

@Test func `the block length choices are the owner's eight`() {
    #expect(WorkspaceRoster.blockLengthChoices == [25, 30, 45, 60, 90, 120, 180, 240])
}

@Test(arguments: [25, 60, 240])
func `a stored length in the list leaves the choices as they are`(minutes: Int) {
    #expect(WorkspaceRoster.blockLengthChoices(including: minutes) == WorkspaceRoster.blockLengthChoices)
}

@Test func `a stored length outside the list is kept in its sorted place`() {
    #expect(WorkspaceRoster.blockLengthChoices(including: 50) == [25, 30, 45, 50, 60, 90, 120, 180, 240])
    #expect(WorkspaceRoster.blockLengthChoices(including: 10) == [10, 25, 30, 45, 60, 90, 120, 180, 240])
    #expect(WorkspaceRoster.blockLengthChoices(including: 300) == [25, 30, 45, 60, 90, 120, 180, 240, 300])
    #expect(WorkspaceRoster.blockLengthChoices(including: 0).first == 0)
}

// MARK: - Order

@Test func `moving reorders like a list's drag and drop`() {
    let items = ["A", "B", "C", "D"]
    #expect(WorkspaceRoster.moved(items, fromOffsets: [0], toOffset: 4) == ["B", "C", "D", "A"])
    #expect(WorkspaceRoster.moved(items, fromOffsets: [3], toOffset: 0) == ["D", "A", "B", "C"])
    #expect(WorkspaceRoster.moved(items, fromOffsets: [1], toOffset: 3) == ["A", "C", "B", "D"])
    #expect(WorkspaceRoster.moved(items, fromOffsets: [1], toOffset: 1) == items)
    #expect(WorkspaceRoster.moved(items, fromOffsets: [1], toOffset: 2) == items)
    #expect(WorkspaceRoster.moved(items, fromOffsets: [0, 2], toOffset: 4) == ["B", "D", "A", "C"])
}

@Test func `moving one item lands it before the destination for every single drag`() {
    let items = ["A", "B", "C", "D", "E"]
    for source in items.indices {
        for destination in 0 ... items.count {
            var expected = items
            let item = expected.remove(at: source)
            expected.insert(item, at: destination > source ? destination - 1 : destination)
            #expect(WorkspaceRoster.moved(items, fromOffsets: [source], toOffset: destination) == expected)
        }
    }
}

@Test func `offsets outside the list are ignored and the destination is clamped`() {
    let items = ["A", "B", "C"]
    #expect(WorkspaceRoster.moved(items, fromOffsets: [7], toOffset: 0) == items)
    #expect(WorkspaceRoster.moved(items, fromOffsets: [0], toOffset: 99) == ["B", "C", "A"])
    #expect(WorkspaceRoster.moved(items, fromOffsets: [2], toOffset: -5) == ["C", "A", "B"])
    #expect(WorkspaceRoster.moved([String](), fromOffsets: [0], toOffset: 0) == [])
}

@Test func `moving a workspace renumbers the active ones densely and saves`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)

    try roster.move(fromOffsets: [2], toOffset: 0)

    #expect(try names(roster) == ["Personal", "Acme", "Globex"])
    #expect(try sortOrders(roster) == [0, 1, 2])
    #expect(!context.hasChanges)
    #expect(try roster.activeWorkspaces().indices.map(WorkspaceRoster.quickStartKey(at:)) == [1, 2, 3])
}

@Test func `gaps in a stored order are closed by the next move`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)
    for (workspace, order) in try zip(roster.activeWorkspaces(), [3, 7, 20]) {
        workspace.sortOrder = order
    }
    try context.save()

    try roster.move(fromOffsets: [0], toOffset: 3)

    #expect(try names(roster) == ["Globex", "Personal", "Acme"])
    #expect(try sortOrders(roster) == [0, 1, 2])
}

// MARK: - Archive and restore

@Test func `archiving hides a workspace, closes the gap and keeps its history`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)
    let acme = try roster.activeWorkspaces()[0]
    let blockIDs = Set(acme.blocks?.map(\.id) ?? [])
    let entryIDs = Set(acme.entries?.map(\.id) ?? [])
    #expect(blockIDs.count == 1)
    #expect(entryIDs.count == 4)

    try roster.archive(acme)

    #expect(try names(roster) == ["Globex", "Personal"])
    #expect(try sortOrders(roster) == [0, 1])
    #expect(acme.isArchived)
    #expect(!context.hasChanges)
    let reread = try #require(everyWorkspace(ModelContext(context.container)).first { $0.id == acme.id })
    #expect(reread.isArchived)
    #expect(Set(reread.blocks?.map(\.id) ?? []) == blockIDs)
    #expect(Set(reread.entries?.map(\.id) ?? []) == entryIDs)
    #expect(reread.projects?.count == 2)
}

@Test func `restoring brings a workspace back last with its history`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)
    let acme = try roster.activeWorkspaces()[0]
    let entryIDs = Set(acme.entries?.map(\.id) ?? [])
    try roster.archive(acme)

    try roster.restore(acme)

    #expect(try names(roster) == ["Globex", "Personal", "Acme"])
    #expect(try sortOrders(roster) == [0, 1, 2])
    #expect(WorkspaceRoster.quickStartKey(at: 2) == 3)
    let reread = try #require(everyWorkspace(ModelContext(context.container)).first { $0.id == acme.id })
    #expect(!reread.isArchived)
    #expect(Set(reread.entries?.map(\.id) ?? []) == entryIDs)
    #expect(reread.blocks?.first?.entries?.count == 3)
    #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 5)
    #expect(try context.fetchCount(FetchDescriptor<TimeBlock>()) == 3)
}

@Test func `archiving twice or restoring an active workspace changes nothing`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)
    let active = try roster.activeWorkspaces()
    try roster.archive(active[0])

    try roster.archive(active[0])
    try roster.restore(active[1])

    #expect(try names(roster) == ["Globex", "Personal"])
    #expect(try sortOrders(roster) == [0, 1])
}

@Test func `archiving every workspace leaves none active and deletes none`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)
    for workspace in try roster.activeWorkspaces() {
        try roster.archive(workspace)
    }

    #expect(try roster.activeWorkspaces().isEmpty)
    #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 3)
    #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 5)
}

@Test func `no roster operation ever deletes a workspace or its history`() throws {
    let context = try sampleContext()
    let roster = WorkspaceRoster(context: context)
    let counts = {
        try [
            context.fetchCount(FetchDescriptor<Workspace>()),
            context.fetchCount(FetchDescriptor<Project>()),
            context.fetchCount(FetchDescriptor<TimeBlock>()),
            context.fetchCount(FetchDescriptor<TimeEntry>()),
        ]
    }
    let before = try counts()

    let created = try roster.create(baseName: "Acme")
    try roster.move(fromOffsets: [3], toOffset: 0)
    for workspace in try roster.activeWorkspaces() {
        try roster.archive(workspace)
    }
    for workspace in try everyWorkspace(context) {
        try roster.restore(workspace)
    }
    try roster.archive(created)

    #expect(try counts() == [before[0] + 1] + before.dropFirst())
}

// MARK: - After a restart

@Test func `created, renamed, recolored, moved and archived workspaces survive reopening the store`() throws {
    let folder = FileManager.default.temporaryDirectory
        .appending(path: "DontBurnCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: "Store", directoryHint: .isDirectory)
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) } // Cleanup only.

    do {
        let context = try ModelContext(ModelStore.onDisk(in: folder))
        let roster = WorkspaceRoster(context: context)
        let acme = try roster.create(baseName: "New workspace")
        acme.name = "Acme"
        let globex = try roster.create(baseName: "New workspace")
        globex.name = "Globex"
        globex.color = .raspberry
        globex.defaultBlockMinutes = 50
        let personal = try roster.create(baseName: "New workspace")
        personal.name = "Personal"
        try context.save()
        try roster.move(fromOffsets: [2], toOffset: 0)
        try roster.archive(acme)
    }

    let roster = try WorkspaceRoster(context: ModelContext(ModelStore.onDisk(in: folder)))
    let active = try roster.activeWorkspaces()
    #expect(active.map(\.name) == ["Personal", "Globex"])
    #expect(active.map(\.sortOrder) == [0, 1])
    #expect(active.map(\.color) == [.orange, .raspberry])
    #expect(active[1].defaultBlockMinutes == 50)
    let archived = try ModelContext(ModelStore.onDisk(in: folder))
        .fetch(FetchDescriptor<Workspace>(predicate: #Predicate { $0.isArchived }))
    #expect(archived.map(\.name) == ["Acme"])
    #expect(archived.first?.color == .teal)
}
