@testable import DontBurnCore
import Foundation
import SwiftData
import Testing

/// Acme with Web shop and Mobile app, Globex with Data platform, Personal with Side project.
private struct Sample {
    let acme = Workspace(name: "Acme", color: .teal)
    let globex = Workspace(name: "Globex", color: .indigo, sortOrder: 1)
    let personal = Workspace(name: "Personal", color: .ochre, sortOrder: 2)
    let webShop: Project
    let mobileApp: Project
    let dataPlatform: Project
    let sideProject: Project

    init() {
        webShop = Project(name: "Web shop", workspace: acme)
        mobileApp = Project(name: "Mobile app", workspace: acme, sortOrder: 1)
        dataPlatform = Project(name: "Data platform", workspace: globex)
        sideProject = Project(name: "Side project", workspace: personal)
    }

    var projects: [Project] {
        [webShop, mobileApp, dataPlatform, sideProject]
    }
}

private func folder(_ path: String, of project: Project) -> ProjectFolder {
    ProjectFolder(projectID: project.id, path: path)
}

private func holding(_ path: String, _ folders: [ProjectFolder], _ projects: [Project]) -> String? {
    ProjectFolders.project(holdingResolved: path, folders: folders, projects: projects)?.name
}

/// A local store in memory and the folders kept in it.
private struct Store {
    let context: ModelContext
    let folders: ProjectFolders

    init() throws {
        context = try ModelContext(ModelStore.localInMemory())
        folders = ProjectFolders(context: context)
    }

    func all() throws -> [ProjectFolder] {
        try context.fetch(FetchDescriptor<ProjectFolder>(sortBy: [SortDescriptor(\.path)]))
    }
}

// MARK: - The folder rule

@Test func `a subfolder belongs to the project whose folder holds it`() {
    let desk = Sample()
    let folders = [folder("/code/acme-web", of: desk.webShop), folder("/code/globex-data", of: desk.dataPlatform)]

    #expect(holding("/code/acme-web/src/app", folders, desk.projects) == "Web shop")
    #expect(holding("/code/acme-web", folders, desk.projects) == "Web shop")
    #expect(holding("/code/globex-data/jobs", folders, desk.projects) == "Data platform")
}

@Test func `of two nested project folders the deepest wins, in any order`() {
    let desk = Sample()
    let outer = folder("/code/acme-web", of: desk.webShop)
    let inner = folder("/code/acme-web/mobile", of: desk.mobileApp)

    for folders in [[outer, inner], [inner, outer]] {
        #expect(holding("/code/acme-web/mobile/ios", folders, desk.projects) == "Mobile app")
        #expect(holding("/code/acme-web/mobile", folders, desk.projects) == "Mobile app")
        #expect(holding("/code/acme-web/src", folders, desk.projects) == "Web shop")
        #expect(holding("/code/acme-web", folders, desk.projects) == "Web shop")
    }
}

@Test func `nested folders across workspaces follow the same deepest rule`() {
    let desk = Sample()
    let folders = [folder("/code", of: desk.sideProject), folder("/code/acme-web", of: desk.webShop)]

    #expect(holding("/code/acme-web/src", folders, desk.projects) == "Web shop")
    #expect(holding("/code/notes", folders, desk.projects) == "Side project")
}

@Test func `a folder under no project folder belongs to no project`() {
    let desk = Sample()
    let folders = [folder("/code/acme-web", of: desk.webShop)]

    #expect(holding("/code/acme-website", folders, desk.projects) == nil)
    #expect(holding("/code", folders, desk.projects) == nil)
    #expect(holding("/code/globex-data", folders, desk.projects) == nil)
    #expect(holding("/code/acme-web/src", [], desk.projects) == nil)
}

@Test func `an archived project is skipped and the folder above it wins`() {
    let desk = Sample()
    let folders = [folder("/code/acme-web", of: desk.webShop), folder("/code/acme-web/mobile", of: desk.mobileApp)]
    desk.mobileApp.isArchived = true

    #expect(holding("/code/acme-web/mobile/ios", folders, desk.projects) == "Web shop")

    desk.webShop.isArchived = true
    #expect(holding("/code/acme-web/mobile/ios", folders, desk.projects) == nil)
}

@Test func `a project of an archived workspace is skipped and a parent project's folder wins`() {
    let desk = Sample()
    let folders = [folder("/code", of: desk.sideProject), folder("/code/acme-web", of: desk.webShop)]
    desk.acme.isArchived = true

    #expect(holding("/code/acme-web/src", folders, desk.projects) == "Side project")

    desk.personal.isArchived = true
    #expect(holding("/code/acme-web/src", folders, desk.projects) == nil)
}

@Test func `a project without a workspace, or one not among the projects, holds nothing`() {
    let desk = Sample()
    let orphan = Project(name: "Reading", workspace: nil)
    let folders = [folder("/code/reading", of: orphan), folder("/code/acme-web", of: desk.webShop)]

    #expect(holding("/code/reading/notes", folders, desk.projects + [orphan]) == nil)
    #expect(holding("/code/acme-web/src", folders, [desk.mobileApp]) == nil)
}

@Test func `the rule compares the paths as given and reads nothing from the disk`() {
    let desk = Sample()
    let folders = [folder("/private/var/folders/x/acme-web", of: desk.webShop)]

    #expect(holding("/var/folders/x/acme-web/src", folders, desk.projects) == nil)
    #expect(holding("/private/var/folders/x/acme-web/src", folders, desk.projects) == "Web shop")
}

@Test func `the store resolves the path first, so the var spelling finds a private var folder`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")
    let mobile = try temporary.make("code/acme-web/mobile")
    try store.folders.add(web, to: desk.webShop, among: desk.projects)
    try store.folders.add(mobile, to: desk.mobileApp, among: desk.projects)

    #expect(try store.all().allSatisfy { $0.path.hasPrefix("/private/var/") })
    #expect(try store.folders.project(holding: web + "/src", among: desk.projects)?.name == "Web shop")
    #expect(try store.folders.project(holding: mobile + "/ios/not-made", among: desk.projects)?.name == "Mobile app")
    #expect(try store.folders.project(holding: "/private" + web, among: desk.projects)?.name == "Web shop")
    #expect(try store.folders.project(holding: temporary.path("code"), among: desk.projects) == nil)
}

@Test func `the store finds the project through a symlink to its folder`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")
    let link = temporary.path("acme-link")
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: web)
    try store.folders.add(web, to: desk.webShop, among: desk.projects)

    #expect(try store.folders.project(holding: link + "/src", among: desk.projects)?.name == "Web shop")
}

// MARK: - One project per folder

@Test func `a folder is stored resolved and named by its project's identifier`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")

    try store.folders.add(web + "/", to: desk.webShop, among: desk.projects)

    let stored = try store.all()
    #expect(stored.map(\.path) == [FolderPath.resolved(web)])
    #expect(stored.map(\.projectID) == [desk.webShop.id])
}

@Test func `a folder taken by another project is refused with that project's name`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")
    try store.folders.add(web, to: desk.webShop, among: desk.projects)

    #expect(throws: ProjectFolderError.taken(byProjectNamed: "Web shop")) {
        try store.folders.add(web, to: desk.mobileApp, among: desk.projects)
    }
    #expect(throws: ProjectFolderError.taken(byProjectNamed: "Web shop")) {
        try store.folders.add(web, to: desk.dataPlatform, among: desk.projects)
    }
    #expect(try store.all().map(\.projectID) == [desk.webShop.id])
}

@Test func `a folder stays taken while its project or its workspace is archived`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")
    let data = try temporary.make("code/globex-data")
    try store.folders.add(web, to: desk.webShop, among: desk.projects)
    try store.folders.add(data, to: desk.dataPlatform, among: desk.projects)
    desk.webShop.isArchived = true
    desk.globex.isArchived = true

    #expect(throws: ProjectFolderError.taken(byProjectNamed: "Web shop")) {
        try store.folders.add(web, to: desk.mobileApp, among: desk.projects)
    }
    #expect(throws: ProjectFolderError.taken(byProjectNamed: "Data platform")) {
        try store.folders.add(data, to: desk.sideProject, among: desk.projects)
    }
    #expect(try store.all().count == 2)
}

@Test func `the var spelling of a taken private var folder is refused too`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")
    try store.folders.add("/private" + web, to: desk.webShop, among: desk.projects)

    #expect(throws: ProjectFolderError.taken(byProjectNamed: "Web shop")) {
        try store.folders.add(web, to: desk.mobileApp, among: desk.projects)
    }
    #expect(throws: ProjectFolderError.taken(byProjectNamed: "Web shop")) {
        try store.folders.add(web + "/./", to: desk.mobileApp, among: desk.projects)
    }
}

@Test func `a symlink to a taken folder is refused`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")
    let link = temporary.path("acme-link")
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: web)
    try store.folders.add(web, to: desk.webShop, among: desk.projects)

    #expect(throws: ProjectFolderError.taken(byProjectNamed: "Web shop")) {
        try store.folders.add(link, to: desk.mobileApp, among: desk.projects)
    }
}

@Test func `adding a project's own folder again changes nothing`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")
    try store.folders.add(web, to: desk.webShop, among: desk.projects)
    let first = try #require(store.all().first)

    try store.folders.add(web, to: desk.webShop, among: desk.projects)
    try store.folders.add("/private" + web + "/", to: desk.webShop, among: desk.projects)

    #expect(try store.all().map(\.id) == [first.id])
}

@Test func `a folder inside another project's folder may be given to a project of its own`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")
    let mobile = try temporary.make("code/acme-web/mobile")

    try store.folders.add(web, to: desk.webShop, among: desk.projects)
    try store.folders.add(mobile, to: desk.mobileApp, among: desk.projects)

    #expect(try store.all().map(\.projectID) == [desk.webShop.id, desk.mobileApp.id])
}

@Test func `a removed folder belongs to no project and can be given to another`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")
    try store.folders.add(web, to: desk.webShop, among: desk.projects)

    try store.folders.remove(#require(store.all().first))

    #expect(try store.all().isEmpty)
    #expect(try store.folders.project(holding: web, among: desk.projects) == nil)
    try store.folders.add(web, to: desk.mobileApp, among: desk.projects)
    #expect(try store.folders.project(holding: web, among: desk.projects)?.name == "Mobile app")
}

@Test func `a folder whose project is gone no longer takes the folder`() throws {
    let temporary = try TemporaryFolder()
    let desk = Sample()
    let store = try Store()
    let web = try temporary.make("code/acme-web")
    try store.folders.add(web, to: desk.webShop, among: desk.projects)
    let without = desk.projects.filter { $0.id != desk.webShop.id }

    try store.folders.add(web, to: desk.mobileApp, among: without)

    #expect(try store.folders.project(holding: web, among: without)?.name == "Mobile app")
}

@Test func `the holder is an exact match, never a parent folder`() {
    let desk = Sample()
    let folders = [folder("/code/acme-web", of: desk.webShop)]

    #expect(ProjectFolders.holder(ofResolved: "/code/acme-web/", folders: folders, projects: desk.projects)?.name
        == "Web shop")
    #expect(ProjectFolders.holder(ofResolved: "/code/acme-web/mobile", folders: folders, projects: desk.projects)
        == nil)
    #expect(ProjectFolders.holder(ofResolved: "/code", folders: folders, projects: desk.projects) == nil)
}

// MARK: - The sample folders

/// The sample set in memory with its folders below `root`, in a local store in memory.
private func sampleFolders(root: URL) throws -> (projects: [Project], folders: [ProjectFolder]) {
    let synced = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: synced, now: Date(timeIntervalSince1970: 1_768_466_490))
    let local = try ModelContext(ModelStore.localInMemory())
    try SampleData.seedFolders(into: local, projects: synced, root: root)
    return try (synced.fetch(FetchDescriptor<Project>()), local.fetch(FetchDescriptor<ProjectFolder>()))
}

@Test func `every sample folder is made below the root it is given`() throws {
    let temporary = try TemporaryFolder()
    let root = FolderPath.resolved(temporary.path)

    let (_, folders) = try sampleFolders(root: temporary.url)

    #expect(folders.count == 5)
    for folder in folders {
        #expect(FolderPath.path(folder.path, isInside: root))
        #expect(FileManager.default.fileExists(atPath: folder.path))
    }
}

@Test func `the sample folders hold the nested pair, and Reading has none`() throws {
    let temporary = try TemporaryFolder()
    let root = FolderPath.resolved(temporary.path)

    let (projects, folders) = try sampleFolders(root: temporary.url)

    let names = Dictionary(uniqueKeysWithValues: projects.map { ($0.id, $0.name) })
    let byProject = Dictionary(grouping: folders) { names[$0.projectID] ?? "?" }
        .mapValues { $0.map { String($0.path.dropFirst(root.count)) }.sorted() }
    #expect(byProject == [
        "Web shop": ["/code/acme-web"],
        "Mobile app": ["/code/acme-mobile", "/code/acme-web/mobile"],
        "Data platform": ["/code/globex-data"],
        "Side project": ["/code/side-project"],
    ])
    #expect(holding(root + "/code/acme-web/mobile/ios", folders, projects) == "Mobile app")
    #expect(holding(root + "/code/acme-web/src", folders, projects) == "Web shop")
}

@Test func `seeding the sample folders twice adds nothing the second time`() throws {
    let temporary = try TemporaryFolder()
    let synced = try ModelContext(ModelStore.inMemory())
    try SampleData.seed(into: synced, now: Date(timeIntervalSince1970: 1_768_466_490))
    let local = try ModelContext(ModelStore.localInMemory())

    try SampleData.seedFolders(into: local, projects: synced, root: temporary.url)
    try SampleData.seedFolders(into: local, projects: synced, root: temporary.url)

    #expect(try local.fetchCount(FetchDescriptor<ProjectFolder>()) == 5)
}
