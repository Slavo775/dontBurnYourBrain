@testable import DontBurnCore
import Foundation
import Testing

private let now = Date(timeIntervalSince1970: 1_768_466_490)

private struct Setup {
    let acme = Workspace(name: "Acme", color: .teal)
    let globex = Workspace(name: "Globex", color: .indigo)
    let webShop: Project
    let untracked: Project
    let dataPlatform: Project
    let block: TimeBlock
    let entry: TimeEntry

    init() {
        webShop = Project(name: "Web shop", workspace: acme)
        untracked = Project(name: "Reading", workspace: acme, isTimeTracked: false)
        dataPlatform = Project(name: "Data platform", workspace: globex)
        block = TimeBlock(workspace: acme, plannedStart: now, plannedMinutes: 60)
        entry = TimeEntry(workspace: acme, start: now, end: nil)
    }
}

@Test func `a block or an entry takes a tracked project of its own workspace`() throws {
    let setup = Setup()

    try setup.block.assign(setup.webShop)
    try setup.entry.assign(setup.webShop)

    #expect(setup.block.project === setup.webShop)
    #expect(setup.entry.project === setup.webShop)
}

@Test func `a block is refused a project whose time is not tracked`() {
    let setup = Setup()
    #expect(throws: ProjectAssignmentError.notTimeTracked) { try setup.block.assign(setup.untracked) }
    #expect(setup.block.project == nil)
}

@Test func `an entry is refused a project whose time is not tracked`() {
    let setup = Setup()
    #expect(throws: ProjectAssignmentError.notTimeTracked) { try setup.entry.assign(setup.untracked) }
    #expect(setup.entry.project == nil)
}

@Test func `a block is refused a project of another workspace`() {
    let setup = Setup()
    #expect(throws: ProjectAssignmentError.otherWorkspace) { try setup.block.assign(setup.dataPlatform) }
    #expect(setup.block.project == nil)
}

@Test func `an entry is refused a project of another workspace`() {
    let setup = Setup()
    #expect(throws: ProjectAssignmentError.otherWorkspace) { try setup.entry.assign(setup.dataPlatform) }
    #expect(setup.entry.project == nil)
}

@Test func `another workspace with the same name is still another workspace`() {
    let setup = Setup()
    let twin = Workspace(name: "Acme", color: .teal)
    let twinProject = Project(name: "Web shop", workspace: twin)

    #expect(throws: ProjectAssignmentError.otherWorkspace) { try setup.block.assign(twinProject) }
}

@Test func `a project of another workspace is refused before its tracking is looked at`() {
    let setup = Setup()
    let globexUntracked = Project(name: "Archive", workspace: setup.globex, isTimeTracked: false)

    #expect(throws: ProjectAssignmentError.otherWorkspace) { try setup.entry.assign(globexUntracked) }
}

@Test func `a block or an entry without a workspace is refused any project`() {
    let setup = Setup()
    let block = TimeBlock(workspace: nil, plannedStart: now, plannedMinutes: 30)
    let entry = TimeEntry(workspace: nil, start: now, end: nil)

    #expect(throws: ProjectAssignmentError.otherWorkspace) { try block.assign(setup.webShop) }
    #expect(throws: ProjectAssignmentError.otherWorkspace) { try entry.assign(setup.webShop) }
}

@Test func `a project without a workspace is refused`() {
    let setup = Setup()
    let orphan = Project(name: "Side project", workspace: nil)

    #expect(throws: ProjectAssignmentError.otherWorkspace) { try setup.block.assign(orphan) }
}

@Test func `a refused project leaves the earlier project in place`() throws {
    let setup = Setup()
    try setup.block.assign(setup.webShop)
    try setup.entry.assign(setup.webShop)

    #expect(throws: ProjectAssignmentError.notTimeTracked) { try setup.block.assign(setup.untracked) }
    #expect(throws: ProjectAssignmentError.otherWorkspace) { try setup.entry.assign(setup.dataPlatform) }

    #expect(setup.block.project === setup.webShop)
    #expect(setup.entry.project === setup.webShop)
}

@Test func `assigning nil clears the project, even in a block without a workspace`() throws {
    let setup = Setup()
    try setup.block.assign(setup.webShop)
    try setup.entry.assign(setup.webShop)
    let loose = TimeBlock(workspace: nil, plannedStart: now, plannedMinutes: 30)

    try setup.block.assign(nil)
    try setup.entry.assign(nil)
    try loose.assign(nil)

    #expect(setup.block.project == nil)
    #expect(setup.entry.project == nil)
    #expect(loose.project == nil)
}
