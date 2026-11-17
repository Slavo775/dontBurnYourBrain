@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// 2026-01-15 08:41:30 UTC. Every test date is built from this, never the clock.
private let now = Date(timeIntervalSince1970: 1_768_466_490)

/// One of each model, linked as the app links them.
private struct Graph {
    let workspace = Workspace(name: "Acme", color: .orange, sortOrder: 3)
    let project: Project
    let block: TimeBlock
    let entry: TimeEntry

    init() throws {
        project = Project(name: "Web shop", workspace: workspace, sortOrder: 2)
        block = TimeBlock(workspace: workspace, plannedStart: now, plannedMinutes: 90, state: .running)
        try block.assign(project)
        entry = TimeEntry(
            workspace: workspace, start: now, end: now.addingTimeInterval(1800),
            kind: .meeting, source: .manual, block: block, note: "ACM-412",
        )
        try entry.assign(project)
    }

    func insert(into context: ModelContext) {
        context.insert(workspace)
        context.insert(project)
        context.insert(block)
        context.insert(entry)
    }
}

/// A folder in the temporary directory that the test removes when it ends.
private func temporaryFolder() -> URL {
    FileManager.default.temporaryDirectory
        .appending(path: "DontBurnCoreTests-\(UUID().uuidString)", directoryHint: .isDirectory)
        .appending(path: "Store", directoryHint: .isDirectory)
}

private func counts(_ context: ModelContext) throws -> [Int] {
    try [
        context.fetchCount(FetchDescriptor<Workspace>()),
        context.fetchCount(FetchDescriptor<Project>()),
        context.fetchCount(FetchDescriptor<TimeBlock>()),
        context.fetchCount(FetchDescriptor<TimeEntry>()),
    ]
}

/// Checks that every field and link of the graph came back as it was saved.
private func expectLoaded(_ context: ModelContext) throws {
    let workspace = try #require(context.fetch(FetchDescriptor<Workspace>()).first)
    #expect(workspace.name == "Acme")
    #expect(workspace.color == .orange)
    #expect(workspace.sortOrder == 3)
    #expect(workspace.defaultBlockMinutes == 60)
    #expect(workspace.roundingStepMinutes == 15)
    #expect(workspace.breaksCount)
    #expect(!workspace.isArchived)

    let project = try #require(workspace.projects?.first)
    #expect(project.name == "Web shop")
    #expect(project.sortOrder == 2)
    #expect(project.isTimeTracked)

    let block = try #require(workspace.blocks?.first)
    #expect(block.plannedStart == now)
    #expect(block.plannedMinutes == 90)
    #expect(block.state == .running)
    #expect(block.project?.id == project.id)

    let entry = try #require(workspace.entries?.first)
    #expect(entry.start == now)
    #expect(entry.end == now.addingTimeInterval(1800))
    #expect(entry.kind == .meeting)
    #expect(entry.source == .manual)
    #expect(entry.note == "ACM-412")
    #expect(entry.project?.id == project.id)
    #expect(entry.block?.id == block.id)
    #expect(block.entries?.count == 1)
}

private func deleteAll(_ context: ModelContext) throws {
    try context.delete(model: TimeEntry.self)
    try context.delete(model: TimeBlock.self)
    try context.delete(model: Project.self)
    try context.delete(model: Workspace.self)
    try context.save()
}

// MARK: - Create, save, load, delete

@Test func `a workspace, project, block and entry are created, saved, loaded and deleted in memory`() throws {
    let container = try ModelStore.inMemory()
    let writer = ModelContext(container)
    try Graph().insert(into: writer)
    try writer.save()

    let reader = ModelContext(container)
    #expect(try counts(reader) == [1, 1, 1, 1])
    try expectLoaded(reader)

    try deleteAll(reader)
    #expect(try counts(ModelContext(container)) == [0, 0, 0, 0])
}

@Test func `a workspace, project, block and entry survive closing and reopening a store on disk`() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) } // Cleanup only.
    #expect(!FileManager.default.fileExists(atPath: folder.path()))

    do {
        let context = try ModelContext(ModelStore.onDisk(in: folder))
        try Graph().insert(into: context)
        try context.save()
    }
    #expect(FileManager.default.fileExists(atPath: folder.appending(path: ModelStore.fileName).path()))

    do {
        let context = try ModelContext(ModelStore.onDisk(in: folder))
        #expect(try counts(context) == [1, 1, 1, 1])
        try expectLoaded(context)
        try deleteAll(context)
    }

    let reopened = try ModelContext(ModelStore.onDisk(in: folder))
    #expect(try counts(reopened) == [0, 0, 0, 0])
}

@Test func `the store on disk is named DontBurn.store inside the folder it is given`() throws {
    let folder = temporaryFolder()
    defer { try? FileManager.default.removeItem(at: folder.deletingLastPathComponent()) } // Cleanup only.

    let container = try ModelStore.onDisk(in: folder)

    let url = try #require(container.configurations.first?.url)
    #expect(url.lastPathComponent == "DontBurn.store")
    #expect(url.deletingLastPathComponent().standardizedFileURL.path() == folder.standardizedFileURL.path())
}

@Test func `a store whose folder cannot be made throws instead of crashing`() throws {
    let parent = temporaryFolder().deletingLastPathComponent()
    defer { try? FileManager.default.removeItem(at: parent) } // Cleanup only.
    try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: true)
    let blocked = parent.appending(path: "Store", directoryHint: .notDirectory)
    try Data("x".utf8).write(to: blocked)

    #expect(throws: (any Error).self) { try ModelStore.onDisk(in: blocked) }
}

@Test func `separate in-memory stores share nothing`() throws {
    let first = try ModelContext(ModelStore.inMemory())
    try Graph().insert(into: first)
    try first.save()

    #expect(try counts(ModelContext(ModelStore.inMemory())) == [0, 0, 0, 0])
}

// MARK: - Delete rules

@Test func `deleting a workspace deletes its projects, blocks and entries`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    let graph = try Graph()
    graph.insert(into: context)
    let globex = Workspace(name: "Globex", color: .indigo)
    context.insert(globex)
    context.insert(Project(name: "Data platform", workspace: globex))
    try context.save()

    context.delete(graph.workspace)
    try context.save()

    #expect(try counts(context) == [1, 1, 0, 0])
    #expect(try context.fetch(FetchDescriptor<Project>()).first?.name == "Data platform")
}

@Test func `deleting a project keeps its blocks and entries and clears their project`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    let graph = try Graph()
    graph.insert(into: context)
    try context.save()

    context.delete(graph.project)
    try context.save()

    #expect(try counts(context) == [1, 0, 1, 1])
    #expect(graph.block.project == nil)
    #expect(graph.entry.project == nil)
    #expect(graph.entry.workspace?.id == graph.workspace.id)
}

@Test func `deleting a block keeps its entries and clears their block`() throws {
    let context = try ModelContext(ModelStore.inMemory())
    let graph = try Graph()
    graph.insert(into: context)
    try context.save()

    context.delete(graph.block)
    try context.save()

    #expect(try counts(context) == [1, 1, 0, 1])
    #expect(graph.entry.block == nil)
    #expect(graph.entry.project?.id == graph.project.id)
}

// MARK: - Rules for iCloud sync

/// Every way `schema` breaks the rules iCloud sync needs.
private func syncViolations(in schema: Schema) -> [String] {
    var found: [String] = []
    for entity in schema.entities {
        if !entity.uniquenessConstraints.isEmpty {
            found.append("\(entity.name) has a uniqueness constraint")
        }
        for attribute in entity.attributes {
            if attribute.isUnique {
                found.append("\(entity.name).\(attribute.name) is unique")
            }
            if !attribute.isOptional, attribute.defaultValue == nil {
                found.append("\(entity.name).\(attribute.name) has no default and is not optional")
            }
        }
        for relationship in entity.relationships {
            if !relationship.isOptional {
                found.append("\(entity.name).\(relationship.name) is not optional")
            }
            if relationship.inverseName == nil, relationship.inverseKeyPath == nil {
                found.append("\(entity.name).\(relationship.name) has no inverse")
            }
        }
    }
    return found
}

@Test func `the schema follows the rules iCloud sync needs`() {
    #expect(syncViolations(in: ModelStore.schema) == [])
}

@Test func `the schema holds exactly the four models`() {
    let names = Set(ModelStore.schema.entities.map(\.name))
    #expect(names == ["Workspace", "Project", "TimeBlock", "TimeEntry"])
    #expect(SchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    #expect(DontBurnMigrationPlan.schemas.count == 1)
    #expect(DontBurnMigrationPlan.stages.isEmpty)
}

/// Models that break every sync rule, so the walk is shown to catch each one.
@Model private final class BrokenOwner {
    @Attribute(.unique) var key = ""
    var label: String
    @Relationship(inverse: \BrokenItem.owner) var items: [BrokenItem]?

    init(label: String) {
        self.label = label
    }
}

@Model private final class BrokenItem {
    var owner: BrokenOwner

    init(owner: BrokenOwner) {
        self.owner = owner
    }
}

@Test func `the schema walk catches a unique attribute, a required relationship and a missing default`() {
    let found = syncViolations(in: Schema([BrokenOwner.self, BrokenItem.self]))

    #expect(found.contains("BrokenOwner.key is unique"))
    #expect(found.contains("BrokenOwner.label has no default and is not optional"))
    #expect(found.contains("BrokenItem.owner is not optional"))
}
