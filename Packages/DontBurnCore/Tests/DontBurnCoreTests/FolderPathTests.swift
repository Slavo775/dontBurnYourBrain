@testable import DontBurnCore
import Foundation
import Testing

// MARK: - Resolving symlinks

@Test func `the var and private var spellings of one real folder resolve to the same path`() throws {
    let temporary = try TemporaryFolder()
    let made = try temporary.make("code/acme-web")
    try #require(made.hasPrefix("/var/"))
    let privateSpelling = "/private" + made

    let resolved = FolderPath.resolved(made)

    #expect(resolved.hasPrefix("/private/var/"))
    #expect(resolved.hasSuffix("/code/acme-web"))
    #expect(FolderPath.resolved(privateSpelling) == resolved)
}

@Test func `a symlink to a folder resolves to the folder it points to`() throws {
    let temporary = try TemporaryFolder()
    let target = try temporary.make("code/acme-web")
    let link = temporary.path("acme-link")
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

    #expect(FolderPath.resolved(link) == FolderPath.resolved(target))
    #expect(FolderPath.resolved(link + "/") == FolderPath.resolved(target))
}

@Test func `a folder not made yet resolves its deepest existing parent and keeps the rest`() throws {
    let temporary = try TemporaryFolder()
    let parent = try temporary.make("code/acme-web")

    let resolved = FolderPath.resolved(parent + "/not-made/./deeper/")

    #expect(resolved == FolderPath.resolved(parent) + "/not-made/deeper")
    #expect(resolved.hasPrefix("/private/var/"))
}

@Test func `a missing folder below a symlink resolves through the symlink`() throws {
    let temporary = try TemporaryFolder()
    let target = try temporary.make("code/acme-web")
    let link = temporary.path("acme-link")
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

    #expect(FolderPath.resolved(link + "/mobile") == FolderPath.resolved(target) + "/mobile")
}

@Test func `a path under no existing folder but the root comes back standardized`() {
    let missing = "/DontBurnCoreTests-\(UUID().uuidString)"

    #expect(FolderPath.resolved(missing + "//code/./acme-web/../globex-data/") == missing + "/code/globex-data")
}

@Test func `a relative path is only standardized, never resolved against the working folder`() {
    #expect(FolderPath.resolved("code/./acme-web/") == "/code/acme-web")
    #expect(FolderPath.resolved("") == "/")
}

// MARK: - Standardizing

@Test func `standardizing drops dots, repeated slashes and a trailing slash`() {
    #expect(FolderPath.standardized("/code//acme-web/") == "/code/acme-web")
    #expect(FolderPath.standardized("/code/./acme-web/src/..") == "/code/acme-web")
    #expect(FolderPath.standardized("/../code") == "/code")
    #expect(FolderPath.standardized("/") == "/")
}

@Test func `standardizing keeps a symlink as it is`() throws {
    let temporary = try TemporaryFolder()
    let target = try temporary.make("code/acme-web")
    let link = temporary.path("acme-link")
    try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: target)

    #expect(FolderPath.standardized(link) == link)
}

// MARK: - Containment

@Test func `a folder holds itself and everything below it`() {
    #expect(FolderPath.path("/code/acme-web", isInside: "/code/acme-web"))
    #expect(FolderPath.path("/code/acme-web/", isInside: "/code/acme-web"))
    #expect(FolderPath.path("/code/acme-web/src/app", isInside: "/code/acme-web"))
    #expect(FolderPath.path("/code/acme-web/src", isInside: "/"))
}

@Test func `containment is by whole names, so acme does not hold acme-web`() {
    #expect(!FolderPath.path("/code/acme-web", isInside: "/code/acme"))
    #expect(!FolderPath.path("/code/acme-web/src", isInside: "/code/acme"))
    #expect(!FolderPath.path("/code/acme", isInside: "/code/acme-web"))
}

@Test func `a parent is not inside its child, and a sibling is not inside either`() {
    #expect(!FolderPath.path("/code", isInside: "/code/acme-web"))
    #expect(!FolderPath.path("/code/globex-data", isInside: "/code/acme-web"))
    #expect(!FolderPath.path("/", isInside: "/code"))
}

@Test func `containment compares text only and does not resolve symlinks`() {
    #expect(!FolderPath.path("/var/folders/x", isInside: "/private/var/folders"))
    #expect(FolderPath.path(FolderPath.standardized("/code/acme-web/src/.."), isInside: "/code/acme-web"))
}
