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

private func workspace(_ name: String, in context: ModelContext) throws -> Workspace {
    try #require(context.fetch(FetchDescriptor<Workspace>()).first { $0.name == name })
}

private func project(_ name: String, in context: ModelContext) throws -> Project {
    try #require(context.fetch(FetchDescriptor<Project>()).first { $0.name == name })
}

private func active(_ workspace: Workspace, in context: ModelContext) throws -> [Project] {
    try ProjectRoster.active(context.fetch(FetchDescriptor<Project>()), in: workspace)
}

private func archived(_ workspace: Workspace, in context: ModelContext) throws -> [Project] {
    try ProjectRoster.archived(context.fetch(FetchDescriptor<Project>()), in: workspace)
}

// MARK: - Create

@Test func `a new project is named New project, then New project 2, and its time is tracked`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)

    let first = try roster.create(baseName: "New project", in: acme)
    let second = try roster.create(baseName: "New project", in: acme)

    #expect(first.name == "New project")
    #expect(second.name == "New project 2")
    #expect(first.isTimeTracked && second.isTimeTracked)
    #expect(!first.isArchived && !second.isArchived)
    #expect(first.workspace?.id == acme.id)
}

@Test func `an archived name in the same workspace counts as taken`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)
    let first = try roster.create(baseName: "New project", in: acme)
    try roster.archive(first)

    #expect(try roster.create(baseName: "New project", in: acme).name == "New project 2")
    #expect(try roster.create(baseName: "Web shop", in: acme).name == "Web shop 2")
}

@Test func `a name used only in another workspace is free`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    try roster.create(baseName: "New project", in: workspace("Acme", in: context))

    let globex = try roster.create(baseName: "New project", in: workspace("Globex", in: context))

    #expect(globex.name == "New project")
    #expect(try roster.create(baseName: "Web shop", in: workspace("Globex", in: context)).name == "Web shop")
}

@Test func `a new project goes last, and the active projects keep a dense order from 0`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)

    try roster.create(baseName: "New project", in: acme)

    #expect(try active(acme, in: context).map(\.name) == ["Web shop", "Mobile app", "New project"])
    #expect(try active(acme, in: context).map(\.sortOrder) == [0, 1, 2])
}

@Test func `a sparse order is made dense again by the next create`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)
    try project("Web shop", in: context).sortOrder = 7
    try project("Mobile app", in: context).sortOrder = 3
    try context.save()

    try roster.create(baseName: "New project", in: acme)

    #expect(try active(acme, in: context).map(\.name) == ["Mobile app", "Web shop", "New project"])
    #expect(try active(acme, in: context).map(\.sortOrder) == [0, 1, 2])
}

@Test func `the first project of a workspace without any starts at 0`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let fresh = Workspace(name: "New workspace", color: .slate, sortOrder: 3)
    context.insert(fresh)
    try context.save()

    let first = try roster.create(baseName: "New project", in: fresh)

    #expect(first.sortOrder == 0)
    #expect(try active(fresh, in: context).map(\.name) == ["New project"])
    #expect(try active(workspace("Acme", in: context), in: context).map(\.sortOrder) == [0, 1])
}

// MARK: - Move

@Test func `moving reorders the active projects and keeps the order dense`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)
    try roster.create(baseName: "Checkout", in: acme)

    try roster.move(in: acme, fromOffsets: [0], toOffset: 3)
    #expect(try active(acme, in: context).map(\.name) == ["Mobile app", "Checkout", "Web shop"])

    try roster.move(in: acme, fromOffsets: [2], toOffset: 0)
    #expect(try active(acme, in: context).map(\.name) == ["Web shop", "Mobile app", "Checkout"])
    #expect(try active(acme, in: context).map(\.sortOrder) == [0, 1, 2])
}

@Test func `moving in one workspace leaves the others alone`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let personal = try workspace("Personal", in: context)
    let before = try context.fetch(FetchDescriptor<Project>()).filter { $0.workspace?.name != "Personal" }
        .map { "\($0.name) \($0.sortOrder)" }.sorted()

    try roster.move(in: personal, fromOffsets: [1], toOffset: 0)

    let after = try context.fetch(FetchDescriptor<Project>()).filter { $0.workspace?.name != "Personal" }
        .map { "\($0.name) \($0.sortOrder)" }.sorted()
    #expect(after == before)
    #expect(try active(personal, in: context).map(\.name) == ["Reading", "Side project"])
}

@Test func `an archived project takes no place in the order a move works on`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)
    try roster.create(baseName: "Checkout", in: acme)
    try roster.archive(project("Web shop", in: context))

    try roster.move(in: acme, fromOffsets: [1], toOffset: 0)

    #expect(try active(acme, in: context).map(\.name) == ["Checkout", "Mobile app"])
    #expect(try active(acme, in: context).map(\.sortOrder) == [0, 1])
}

// MARK: - Archive and restore

@Test func `archiving takes a project out of the active list and renumbers the rest`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)
    try roster.create(baseName: "Checkout", in: acme)

    try roster.archive(project("Web shop", in: context))

    #expect(try project("Web shop", in: context).isArchived)
    #expect(try active(acme, in: context).map(\.name) == ["Mobile app", "Checkout"])
    #expect(try active(acme, in: context).map(\.sortOrder) == [0, 1])
    #expect(try archived(acme, in: context).map(\.name) == ["Web shop"])
}

@Test func `archiving an archived project changes nothing`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)
    let webShop = try project("Web shop", in: context)
    try roster.archive(webShop)
    let order = webShop.sortOrder

    try roster.archive(webShop)

    #expect(webShop.isArchived)
    #expect(webShop.sortOrder == order)
    #expect(try active(acme, in: context).map(\.sortOrder) == [0])
}

@Test func `restoring puts the project back last, unchanged`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)
    let webShop = try project("Web shop", in: context)
    webShop.isTimeTracked = false
    try roster.create(baseName: "Checkout", in: acme)
    try roster.archive(webShop)

    try roster.restore(webShop)

    #expect(!webShop.isArchived)
    #expect(!webShop.isTimeTracked)
    #expect(webShop.name == "Web shop")
    #expect(try active(acme, in: context).map(\.name) == ["Mobile app", "Checkout", "Web shop"])
    #expect(try active(acme, in: context).map(\.sortOrder) == [0, 1, 2])
    #expect(try archived(acme, in: context).isEmpty)
}

@Test func `restoring an active project changes nothing`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)

    try roster.restore(project("Web shop", in: context))

    #expect(try active(acme, in: context).map(\.name) == ["Web shop", "Mobile app"])
    #expect(try active(acme, in: context).map(\.sortOrder) == [0, 1])
}

@Test func `archived projects are listed by name, numbers in number order`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)
    for _ in 0 ..< 10 {
        try roster.archive(roster.create(baseName: "Project", in: acme))
    }

    let names = try archived(acme, in: context).map(\.name)

    #expect(names.prefix(3) == ["Project", "Project 2", "Project 3"])
    #expect(names.last == "Project 10")
    #expect(try archived(workspace("Globex", in: context), in: context).isEmpty)
}

@Test func `a project of an archived workspace still lists as active in its own workspace`() throws {
    let context = try sampleContext()
    let globex = try workspace("Globex", in: context)
    globex.isArchived = true

    #expect(try active(globex, in: context).map(\.name) == ["Data platform"])
}

// MARK: - Nothing is deleted

@Test func `create, move, archive and restore never delete a project or its history`() throws {
    let context = try sampleContext()
    let roster = ProjectRoster(context: context)
    let acme = try workspace("Acme", in: context)
    let webShop = try project("Web shop", in: context)
    let entries = webShop.entries?.count
    let blocks = webShop.blocks?.count

    try roster.create(baseName: "Checkout", in: acme)
    try roster.move(in: acme, fromOffsets: [0], toOffset: 3)
    try roster.archive(webShop)
    #expect(webShop.entries?.count == entries)
    #expect(webShop.blocks?.count == blocks)
    try roster.restore(webShop)

    #expect(try context.fetchCount(FetchDescriptor<Project>()) == 6)
    #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 5)
    #expect(webShop.entries?.count == entries)
    #expect(webShop.blocks?.count == blocks)
    #expect(entries == 2)
    #expect(blocks == 1)
}

// MARK: - Track time

@Test func `switching Track time off keeps the project's entries and blocks`() throws {
    let container = try ModelStore.inMemory()
    let context = ModelContext(container)
    try SampleData.seed(into: context, now: sampleNow)
    let webShop = try project("Web shop", in: context)

    webShop.isTimeTracked = false
    try context.save()

    let reread = ModelContext(container)
    let stored = try project("Web shop", in: reread)
    #expect(!stored.isTimeTracked)
    #expect(stored.entries?.count == 2)
    #expect(stored.blocks?.count == 1)
    #expect(try reread.fetch(FetchDescriptor<TimeEntry>()).count { $0.project?.id == stored.id } == 2)
    #expect(try reread.fetch(FetchDescriptor<TimeBlock>()).count { $0.project?.id == stored.id } == 1)
}

@Test func `an untracked project refuses new work but keeps what it had`() throws {
    let context = try sampleContext()
    let webShop = try project("Web shop", in: context)
    let acme = try workspace("Acme", in: context)
    webShop.isTimeTracked = false
    try context.save()
    let entry = TimeEntry(workspace: acme, start: sampleNow, end: nil)

    #expect(throws: ProjectAssignmentError.notTimeTracked) { try entry.assign(webShop) }
    #expect(webShop.entries?.count == 2)

    webShop.isTimeTracked = true
    try entry.assign(webShop)
    #expect(entry.project?.id == webShop.id)
}
