@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

private let now = Date(timeIntervalSince1970: 1_768_466_490)

private func seeded() throws -> ModelContext {
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: now)
    return context
}

// MARK: - The launch argument

@Test(arguments: ["YES", "yes", "Yes", "true", "TRUE", "1"])
func `the sample data is turned on by yes, true or 1 in any case`(raw: String) {
    #expect(SampleData.isRequested(by: raw))
}

@Test(arguments: [
    nil, "", "NO", "no", "0", "false", "y", " YES", "YES ", "YESS", "11", "on",
    String(repeating: "YES", count: 10000),
])
func `the sample data stays off without the argument or with any other value`(raw: String?) {
    #expect(!SampleData.isRequested(by: raw))
}

// MARK: - The seeded set

@Test func `the sample set holds three workspaces, five projects, three blocks and five entries`() throws {
    let context = try seeded()

    #expect(try context.fetchCount(FetchDescriptor<Workspace>()) == 3)
    #expect(try context.fetchCount(FetchDescriptor<Project>()) == 5)
    #expect(try context.fetchCount(FetchDescriptor<TimeBlock>()) == 3)
    #expect(try context.fetchCount(FetchDescriptor<TimeEntry>()) == 5)
}

@Test func `the sample set uses only Acme, Globex and Personal`() throws {
    let context = try seeded()
    let workspaces = try context.fetch(FetchDescriptor<Workspace>(sortBy: [SortDescriptor(\.sortOrder)]))

    #expect(workspaces.map(\.name) == ["Acme", "Globex", "Personal"])
    #expect(workspaces.map(\.color) == [.teal, .indigo, .ochre])
    #expect(workspaces.map(\.breaksCount) == [true, true, false])
    #expect(workspaces.map { $0.projects?.count } == [2, 1, 2])
}

@Test func `the sample set has an untracked project with nothing assigned to it`() throws {
    let projects = try seeded().fetch(FetchDescriptor<Project>())
    let untracked = projects.filter { !$0.isTimeTracked }

    #expect(untracked.map(\.name) == ["Reading"])
    #expect(untracked.first?.workspace?.name == "Personal")
    #expect(untracked.first?.blocks ?? [] == [])
    #expect(untracked.first?.entries ?? [] == [])
}

@Test func `every sample block and entry names a tracked project of its own workspace, or none`() throws {
    let context = try seeded()
    let blocks = try context.fetch(FetchDescriptor<TimeBlock>())
    let entries = try context.fetch(FetchDescriptor<TimeEntry>())

    for block in blocks {
        let project = try #require(block.project)
        #expect(throws: Never.self) { try project.checkAssignable(to: block.workspace) }
    }
    for entry in entries {
        #expect(entry.workspace != nil)
        if let project = entry.project {
            #expect(throws: Never.self) { try project.checkAssignable(to: entry.workspace) }
        }
    }
}

@Test func `the sample entries are all finished before now and cover every kind and source`() throws {
    let entries = try seeded().fetch(FetchDescriptor<TimeEntry>())

    for entry in entries {
        let end = try #require(entry.end)
        #expect(entry.start < end)
        #expect(end <= now)
    }
    #expect(Set(entries.map(\.kind)) == Set(TimeEntryKind.allCases))
    #expect(Set(entries.map(\.source)) == Set(TimeEntrySource.allCases))
}

@Test func `the sample blocks are one done before now and two planned after it`() throws {
    let blocks = try seeded().fetch(FetchDescriptor<TimeBlock>(sortBy: [SortDescriptor(\.plannedStart)]))

    #expect(blocks.map(\.state) == [.done, .planned, .planned])
    #expect(blocks[0].plannedStart < now)
    #expect(blocks.dropFirst().allSatisfy { $0.plannedStart > now })
    #expect(blocks[0].entries?.count == 3)
    #expect(!blocks.contains { $0.state == .running })
}

@Test func `the sample set follows the time it is given`() throws {
    let later = now.addingTimeInterval(86400)
    let first = try seeded().fetch(FetchDescriptor<TimeEntry>()).map(\.start).sorted()
    let context = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: context, now: later)
    let second = try context.fetch(FetchDescriptor<TimeEntry>()).map(\.start).sorted()

    #expect(second == first.map { $0.addingTimeInterval(86400) })
}

// MARK: - Stored values

@Test func `stored values keep the names the schema promises`() {
    #expect(WorkspaceColor.allCases.map(\.rawValue) == ["a", "b", "c", "d", "e", "f"])
    #expect(TimeBlockState.allCases.map(\.rawValue) == ["planned", "running", "done", "cancelled"])
    #expect(TimeEntryKind.allCases.map(\.rawValue) == ["work", "break", "meeting"])
    #expect(TimeEntrySource.allCases.map(\.rawValue) == ["timer", "manual", "calendar"])
}

@Test func `an unknown stored value reads as the first case`() {
    let workspace = Workspace(name: "Acme", color: .slate)
    let block = TimeBlock(workspace: workspace, plannedStart: now, plannedMinutes: 60, state: .done)
    let entry = TimeEntry(workspace: workspace, start: now, end: nil, kind: .meeting, source: .calendar)

    workspace.colorKey = "z"
    block.stateRaw = ""
    entry.kindRaw = "nap"
    entry.sourceRaw = "Timer"

    #expect(workspace.color == .teal)
    #expect(block.state == .planned)
    #expect(entry.kind == .work)
    #expect(entry.source == .timer)
}

@Test func `setting a typed value stores its raw value`() {
    let workspace = Workspace(name: "Acme", color: .teal)
    let block = TimeBlock(workspace: workspace, plannedStart: now, plannedMinutes: 60)
    let entry = TimeEntry(workspace: workspace, start: now, end: nil)

    workspace.color = .raspberry
    block.state = .cancelled
    entry.kind = .break
    entry.source = .manual

    #expect(workspace.colorKey == "d")
    #expect(block.stateRaw == "cancelled")
    #expect(entry.kindRaw == "break")
    #expect(entry.sourceRaw == "manual")
}
