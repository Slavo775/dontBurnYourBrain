@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

// A store written by v0.1.0 holds schema version 1. Version 2 opens it with a
// lightweight stage: every field and link comes back, and the new ones read
// their defaults.

/// The migration plan of v0.1.0, which knew only version 1.
private enum ReleasedMigrationPlan: SchemaMigrationPlan {
    static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    static var stages: [MigrationStage] {
        []
    }
}

/// The identifiers of what ``writeReleasedStore(in:)`` wrote.
private struct WrittenIDs {
    let workspaces: [UUID]
    let projects: [UUID]
    let blocks: [UUID]
    /// Earliest first.
    let entries: [UUID]
}

/// The sample set as v0.1.0 stored it, in the models of version 1.
private struct ReleasedSet {
    let acme = SchemaV1.Workspace(name: "Acme", color: .teal)
    let globex = SchemaV1.Workspace(name: "Globex", color: .indigo, sortOrder: 1)
    let personal = SchemaV1.Workspace(name: "Personal", color: .ochre, sortOrder: 2)
    let webShop: SchemaV1.Project
    let dataPlatform: SchemaV1.Project
    let reading: SchemaV1.Project
    let finished: SchemaV1.TimeBlock
    let planned: SchemaV1.TimeBlock
    let work: SchemaV1.TimeEntry
    let pause: SchemaV1.TimeEntry
    let moreWork: SchemaV1.TimeEntry
    let meeting: SchemaV1.TimeEntry
    let manual: SchemaV1.TimeEntry

    init() {
        acme.defaultBlockMinutes = 90
        globex.roundingStepMinutes = 30
        personal.breaksCount = false
        personal.isArchived = true

        webShop = SchemaV1.Project(name: "Web shop", workspace: acme)
        dataPlatform = SchemaV1.Project(name: "Data platform", workspace: globex)
        reading = SchemaV1.Project(name: "Reading", workspace: personal, isTimeTracked: false, sortOrder: 1)
        reading.isArchived = true

        finished = SchemaV1.TimeBlock(workspace: acme, plannedStart: nine, plannedMinutes: 90, state: .done)
        finished.project = webShop
        planned = SchemaV1.TimeBlock(workspace: globex, plannedStart: at(180), plannedMinutes: 45)
        planned.project = dataPlatform

        work = SchemaV1.TimeEntry(workspace: acme, start: nine, end: at(50), block: finished, note: "ACM-412")
        work.project = webShop
        pause = SchemaV1.TimeEntry(workspace: acme, start: at(50), end: at(55), kind: .break, block: finished)
        pause.plannedMinutes = 5
        moreWork = SchemaV1.TimeEntry(workspace: acme, start: at(55), end: at(90), block: finished)
        moreWork.project = webShop
        meeting = SchemaV1.TimeEntry(
            workspace: globex, start: at(120), end: at(150), kind: .meeting, source: .calendar, note: "GLX-88",
        )
        meeting.project = dataPlatform
        manual = SchemaV1.TimeEntry(
            workspace: personal, start: at(-1440), end: at(-1380), source: .manual, note: "Release checklist",
        )
    }

    /// Every model of the set.
    var models: [any PersistentModel] {
        [
            acme, globex, personal, webShop, dataPlatform, reading, finished, planned,
            work, pause, moreWork, meeting, manual,
        ]
    }

    /// The identifiers of the set.
    var ids: WrittenIDs {
        WrittenIDs(
            workspaces: [acme.id, globex.id, personal.id],
            projects: [webShop.id, dataPlatform.id, reading.id],
            blocks: [finished.id, planned.id],
            entries: [manual.id, work.id, pause.id, moreWork.id, meeting.id],
        )
    }
}

/// Writes the sample set into `folder` with version 1 only, as v0.1.0 did, and closes the store.
private func writeReleasedStore(in folder: URL) throws -> WrittenIDs {
    let schema = Schema(versionedSchema: SchemaV1.self)
    let configuration = ModelConfiguration(
        schema: schema, url: folder.appending(path: ModelStore.fileName), cloudKitDatabase: .none,
    )
    let container = try ModelContainer(
        for: schema, migrationPlan: ReleasedMigrationPlan.self, configurations: configuration,
    )
    let context = ModelContext(container)
    let set = ReleasedSet()
    for model in set.models {
        context.insert(model)
    }
    try context.save()
    return set.ids
}

/// Checks that the sample set came back intact, with every new field at its default and no preset.
private func expectMigrated(_ context: ModelContext, ids: WrittenIDs) throws {
    let workspaces = try context.fetch(FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.sortOrder)]))
    #expect(workspaces.map(\.id) == ids.workspaces)
    #expect(workspaces.map(\.name) == ["Acme", "Globex", "Personal"])
    #expect(workspaces.map(\.color) == [.teal, .indigo, .ochre])
    #expect(workspaces.map(\.defaultBlockMinutes) == [90, 60, 60])
    #expect(workspaces.map(\.roundingStepMinutes) == [15, 30, 15])
    #expect(workspaces.map(\.breaksCount) == [true, true, false])
    #expect(workspaces.map(\.isArchived) == [false, false, true])
    #expect(workspaces.allSatisfy { $0.focusPreset == nil })
    #expect(workspaces.map { $0.projects?.count } == [1, 1, 1])
    #expect(workspaces.map { $0.blocks?.count } == [1, 1, 0])
    #expect(workspaces.map { $0.entries?.count } == [3, 1, 1])

    let projects = try context.fetch(FetchDescriptor<Project>(sortBy: [SortDescriptor(\.name)]))
    #expect(projects.map(\.name) == ["Data platform", "Reading", "Web shop"])
    #expect(projects.map(\.id) == [ids.projects[1], ids.projects[2], ids.projects[0]])
    #expect(projects.map { $0.workspace?.name } == ["Globex", "Personal", "Acme"])
    #expect(projects.map(\.sortOrder) == [0, 1, 0])
    #expect(projects.map(\.isTimeTracked) == [true, false, true])
    #expect(projects.map(\.isArchived) == [false, true, false])

    let migratedBlocks = try blocks(context)
    #expect(migratedBlocks.map(\.id) == ids.blocks)
    #expect(migratedBlocks.map(\.plannedStart) == [nine, at(180)])
    #expect(migratedBlocks.map(\.plannedMinutes) == [90, 45])
    #expect(migratedBlocks.map(\.state) == [.done, .planned])
    #expect(migratedBlocks.map { $0.workspace?.name } == ["Acme", "Globex"])
    #expect(migratedBlocks.map { $0.project?.name } == ["Web shop", "Data platform"])
    #expect(migratedBlocks.map { $0.entries?.count } == [3, 0])
    for block in migratedBlocks {
        #expect(rhythmCopy(of: block) == [0, 0, 0, 0])
        #expect(block.resumesAfterBreak)
        #expect(block.focusPreset == nil)
        #expect(!block.hasRhythm)
    }

    let migratedEntries = try entries(context)
    #expect(migratedEntries.map(\.id) == ids.entries)
    #expect(migratedEntries.map(\.start) == [at(-1440), nine, at(50), at(55), at(120)])
    #expect(migratedEntries.map(\.end) == [at(-1380), at(50), at(55), at(90), at(150)])
    #expect(migratedEntries.map(\.kind) == [.work, .work, .break, .work, .meeting])
    #expect(migratedEntries.map(\.source) == [.manual, .timer, .timer, .timer, .calendar])
    #expect(migratedEntries.map(\.note) == ["Release checklist", "ACM-412", "", "", "GLX-88"])
    #expect(migratedEntries.map(\.plannedMinutes) == [nil, nil, 5, nil, nil])
    #expect(migratedEntries.map { $0.workspace?.name } == ["Personal", "Acme", "Acme", "Acme", "Globex"])
    #expect(migratedEntries.map { $0.project?.name } == [nil, "Web shop", nil, "Web shop", "Data platform"])
    #expect(migratedEntries.map { $0.block?.id } == [nil, ids.blocks[0], ids.blocks[0], ids.blocks[0], nil])

    #expect(try context.fetchCount(FetchDescriptor<FocusPreset>()) == 0)
}

@Test func `a store from 0.1.0 opens in version 2 with its data intact, new fields at defaults and no preset`() throws {
    try withTemporaryFolder { folder in
        let ids = try writeReleasedStore(in: folder.url)

        try expectMigrated(ModelContext(ModelStore.onDisk(in: folder.url)), ids: ids)
        // Opened again, the store is already at version 2 and still holds the same.
        try expectMigrated(ModelContext(ModelStore.onDisk(in: folder.url)), ids: ids)
    }
}

@Test func `after the migration the presets are seeded, no workspace gets one, and a new block has no rhythm`() throws {
    try withTemporaryFolder { folder in
        _ = try writeReleasedStore(in: folder.url)
        let context = try ModelContext(ModelStore.onDisk(in: folder.url))

        try FocusPreset.seedDefaults(into: context)

        #expect(try context.fetch(FetchDescriptor<FocusPreset>()).map(\.id).sorted { $0.uuidString < $1.uuidString }
            == FocusPreset.seededIDs.sorted { $0.uuidString < $1.uuidString })
        let workspaces = try context.fetch(FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.sortOrder)]))
        #expect(workspaces.allSatisfy { $0.focusPreset == nil })
        let engine = TimerEngine(context: context)
        try engine.start(workspaces[0], at: at(300))
        #expect(try engine.settle(at: at(300)).plannedEnd == at(390))
        #expect(try engine.rhythm(at: at(310)) == nil)
    }
}
