@testable import DontBurnCore
import Foundation
import SQLite3
import SwiftData
import Testing

/// 2026-01-15 08:41:30 UTC, the sample data's now.
private let sampleNow = Date(timeIntervalSince1970: 1_768_466_490)

// MARK: - The local store

/// Whether `configuration` names no iCloud database. `CloudKitDatabase` is
/// not `Equatable`, so its description is compared.
private func neverSynced(_ configuration: ModelConfiguration) -> Bool {
    String(describing: configuration.cloudKitDatabase) == String(describing: ModelConfiguration.CloudKitDatabase.none)
}

@Test func `a configuration that may sync is told apart from one that never does`() {
    let synced = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .automatic)
    let local = ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)

    #expect(!neverSynced(synced))
    #expect(neverSynced(local))
}

@Test func `the local store in memory keeps only folders and is never synced`() throws {
    let container = try ModelStore.localInMemory()
    let configuration = try #require(container.configurations.first)

    #expect(container.configurations.count == 1)
    #expect(configuration.isStoredInMemoryOnly)
    #expect(neverSynced(configuration))
    #expect(Set(container.schema.entities.map(\.name)) == ["ProjectFolder"])
}

@Test func `the local store on disk is Local.store beside the synced store, and is never synced`() throws {
    let temporary = try TemporaryFolder()
    let directory = temporary.url.appending(path: "Store", directoryHint: .isDirectory)

    let local = try ModelStore.localOnDisk(in: directory)
    let synced = try ModelStore.onDisk(in: directory)

    let localURL = try #require(local.configurations.first?.url)
    let syncedURL = try #require(synced.configurations.first?.url)
    #expect(localURL.lastPathComponent == "Local.store")
    #expect(localURL.deletingLastPathComponent() == syncedURL.deletingLastPathComponent())
    #expect(try neverSynced(#require(local.configurations.first)))
    #expect(!(local.configurations.first?.isStoredInMemoryOnly ?? true))
    #expect(FileManager.default.fileExists(atPath: temporary.path("Store/Local.store")))
}

@Test func `separate local stores in memory share nothing`() throws {
    let first = try ModelContext(ModelStore.localInMemory())
    first.insert(ProjectFolder(projectID: UUID(), path: "/code/acme-web"))
    try first.save()

    #expect(try ModelContext(ModelStore.localInMemory()).fetchCount(FetchDescriptor<ProjectFolder>()) == 0)
}

@Test func `the local schema is its own first version and follows the sync-ready model rules`() {
    let schema = ModelStore.localSchema
    let folder = schema.entities.first { $0.name == "ProjectFolder" }

    #expect(LocalSchemaV1.versionIdentifier == Schema.Version(1, 0, 0))
    #expect(LocalMigrationPlan.schemas.count == 1)
    #expect(LocalMigrationPlan.stages.isEmpty)
    #expect(Set(folder?.attributes.map(\.name) ?? []) == ["id", "projectID", "path"])
    #expect(folder?.relationships.isEmpty == true)
    #expect(folder?.attributes.allSatisfy { $0.defaultValue != nil || $0.isOptional } == true)
    #expect(folder?.uniquenessConstraints.isEmpty == true)
}

// MARK: - After a restart

@Test func `projects and their folders survive closing and reopening both stores on disk`() throws {
    let temporary = try TemporaryFolder()
    let directory = temporary.url.appending(path: "Store", directoryHint: .isDirectory)
    let web = try temporary.make("code/acme-web")
    let mobile = try temporary.make("code/acme-web/mobile")

    do {
        let synced = try ModelContext(ModelStore.onDisk(in: directory))
        let local = try ModelContext(ModelStore.localOnDisk(in: directory))
        let acme = Workspace(name: "Acme", color: .teal)
        synced.insert(acme)
        let roster = ProjectRoster(context: synced)
        let webShop = try roster.create(baseName: "New project", in: acme)
        webShop.name = "Web shop"
        let mobileApp = try roster.create(baseName: "New project", in: acme)
        mobileApp.name = "Mobile app"
        mobileApp.isTimeTracked = false
        try synced.save()
        try roster.create(baseName: "Checkout", in: acme)
        try roster.move(in: acme, fromOffsets: [2], toOffset: 0)
        try roster.archive(webShop)
        try roster.archive(mobileApp)
        try roster.restore(mobileApp)
        let projects = try synced.fetch(FetchDescriptor<Project>())
        try ProjectFolders(context: local).add(web, to: webShop, among: projects)
        try ProjectFolders(context: local).add(mobile, to: mobileApp, among: projects)
    }

    let synced = try ModelContext(ModelStore.onDisk(in: directory))
    let local = try ModelContext(ModelStore.localOnDisk(in: directory))
    let acme = try #require(synced.fetch(FetchDescriptor<Workspace>()).first)
    let projects = try synced.fetch(FetchDescriptor<Project>())
    let active = ProjectRoster.active(projects, in: acme)
    #expect(active.map(\.name) == ["Checkout", "Mobile app"])
    #expect(active.map(\.sortOrder) == [0, 1])
    #expect(active.map(\.isTimeTracked) == [true, false])
    #expect(ProjectRoster.archived(projects, in: acme).map(\.name) == ["Web shop"])

    let folders = ProjectFolders(context: local)
    #expect(try local.fetchCount(FetchDescriptor<ProjectFolder>()) == 2)
    #expect(try folders.project(holding: mobile + "/ios", among: projects)?.name == "Mobile app")
    #expect(try folders.project(holding: web + "/src", among: projects) == nil)
    #expect(throws: ProjectFolderError.taken(byProjectNamed: "Web shop")) {
        try folders.add(web, to: active[1], among: projects)
    }
}

// MARK: - No path reaches the synced store

/// Every attribute of `schema` that could hold a path: one of type `URL`, or
/// one whose name speaks of a path, folder, directory, file, URL or bookmark.
private func pathAttributes(in schema: Schema) -> [String] {
    let words = ["path", "folder", "director", "file", "url", "bookmark"]
    let urlTypes = [ObjectIdentifier(URL.self), ObjectIdentifier(URL?.self)]
    return schema.entities.flatMap { entity in
        entity.attributes
            .filter { attribute in
                words.contains { attribute.name.lowercased().contains($0) }
                    || urlTypes.contains(ObjectIdentifier(attribute.valueType))
            }
            .map { "\(entity.name).\($0.name)" }
    }
}

@Test func `no attribute of the synced schema could hold a path`() {
    #expect(pathAttributes(in: ModelStore.schema) == [])
    #expect(!ModelStore.schema.entities.contains { $0.name == "ProjectFolder" })
}

@Test func `the synced project keeps only its name, order and two switches`() throws {
    let project = try #require(ModelStore.schema.entities.first { $0.name == "Project" })

    #expect(Set(project.attributes.map(\.name)) == ["id", "name", "sortOrder", "isArchived", "isTimeTracked"])
}

@Test func `the path walk finds the local store's path`() {
    #expect(pathAttributes(in: ModelStore.localSchema) == ["ProjectFolder.path"])
}

private struct StoreReadError: Error {
    let message: String
}

/// Every text value in every table of the SQLite store at `path`, its
/// write-ahead log included.
private func storedTexts(at path: String) throws -> [String] {
    var database: OpaquePointer?
    defer { sqlite3_close(database) }
    guard sqlite3_open_v2(path, &database, SQLITE_OPEN_READONLY, nil) == SQLITE_OK else {
        throw StoreReadError(message: "Could not open \(path)")
    }
    let tables = try rows(of: "SELECT name FROM sqlite_master WHERE type = 'table'", in: database).flatMap(\.self)
    return try tables.flatMap { try rows(of: "SELECT * FROM \"\($0)\"", in: database).flatMap(\.self) }
}

private func rows(of query: String, in database: OpaquePointer?) throws -> [[String]] {
    var statement: OpaquePointer?
    defer { sqlite3_finalize(statement) }
    guard sqlite3_prepare_v2(database, query, -1, &statement, nil) == SQLITE_OK else {
        throw StoreReadError(message: "Could not read \(query)")
    }
    var found: [[String]] = []
    while sqlite3_step(statement) == SQLITE_ROW {
        let columns = 0 ..< sqlite3_column_count(statement)
        found.append(columns.compactMap { column in
            guard sqlite3_column_type(statement, column) == SQLITE_TEXT,
                  let text = sqlite3_column_text(statement, column) else { return nil }
            return String(cString: text)
        })
    }
    return found
}

/// The bytes of every file of the store `name` in `directory`: the store, its log and its index.
private func storeBytes(_ name: String, in directory: String) throws -> [Data] {
    try FileManager.default.contentsOfDirectory(atPath: directory)
        .filter { $0.hasPrefix(name) }
        .map { try Data(contentsOf: URL(filePath: (directory as NSString).appendingPathComponent($0))) }
}

@Test func `with the sample data and its folders seeded, no text in the synced store is a path`() throws {
    let temporary = try TemporaryFolder()
    let directory = temporary.path("Store")
    let root = temporary.url.appending(path: "sample", directoryHint: .isDirectory)
    do {
        let synced = try ModelContext(ModelStore.onDisk(in: URL(filePath: directory, directoryHint: .isDirectory)))
        let local = try ModelContext(ModelStore.localOnDisk(in: URL(filePath: directory, directoryHint: .isDirectory)))
        try SampleData.seed(into: synced, now: sampleNow)
        try SampleData.seedFolders(into: local, projects: synced, root: root)
        #expect(try local.fetchCount(FetchDescriptor<ProjectFolder>()) == 5)
    }
    let marker = Data((temporary.path as NSString).lastPathComponent.utf8)

    let syncedTexts = try storedTexts(at: (directory as NSString).appendingPathComponent(ModelStore.fileName))
    #expect(syncedTexts.contains("Web shop"))
    #expect(syncedTexts.filter { $0.hasPrefix("/") || $0.hasPrefix("~") } == [])
    #expect(try storeBytes(ModelStore.fileName, in: directory).allSatisfy { $0.range(of: marker) == nil })

    // The same reading finds the paths where they belong, in the local store.
    let localTexts = try storedTexts(at: (directory as NSString).appendingPathComponent(ModelStore.localFileName))
    #expect(localTexts.count { $0.hasPrefix("/private/var/") } == 5)
    #expect(try storeBytes(ModelStore.localFileName, in: directory).contains { $0.range(of: marker) != nil })
}
