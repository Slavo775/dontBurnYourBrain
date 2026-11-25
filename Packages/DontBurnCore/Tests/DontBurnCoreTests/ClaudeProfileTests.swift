@testable import DontBurnCore
import Foundation
import Testing

/// A made-up home folder with profiles, other folders and files whose names come close.
private func madeUpHome(_ temporary: TemporaryFolder) throws -> String {
    let home = try temporary.make("home")
    for folder in [".claude-globex", ".claude", ".claude-acme", "claude-personal", ".claudex", ".config", ".claude-"] {
        try temporary.make("home/\(folder)")
    }
    for file in [".claude-notes", ".claude.json"] {
        try Data().write(to: URL(filePath: temporary.path("home/\(file)")))
    }
    return home
}

@Test func `profiles are the folders named .claude or .claude-something at the top of the home folder`() throws {
    try withTemporaryFolder { temporary in
        let home = try madeUpHome(temporary)
        try temporary.make("home/code/.claude-deeper")

        let profiles = ClaudeProfile.find(inHome: home, added: [], allowedFolder: nil)

        #expect(profiles.map(\.name) == [".claude", ".claude-", ".claude-acme", ".claude-globex"])
        #expect(profiles.map(\.folder) == profiles.map { home + "/" + $0.name })
        #expect(profiles.map(\.id) == profiles.map(\.folder))
    }
}

@Test func `a home folder that is missing has no profiles`() {
    let missing = "/DontBurnCoreTests-\(UUID().uuidString)"

    #expect(ClaudeProfile.find(inHome: missing, added: [], allowedFolder: nil).isEmpty)
    #expect(ClaudeProfile.find(inHome: nil, added: [], allowedFolder: "/").isEmpty)
}

@Test func `folders added by hand follow the found ones in their order, each once`() throws {
    try withTemporaryFolder { temporary in
        let home = try temporary.make("home")
        try temporary.make("home/.claude-acme")
        let globex = try temporary.make("work/globex-profile")
        let personal = try temporary.make("work/personal-profile")

        let profiles = ClaudeProfile.find(
            inHome: home,
            added: [personal, "work/relative", home + "/.claude-acme/", globex, personal + "/", "~/.claude-acme"],
            allowedFolder: nil,
        )

        #expect(profiles.map(\.folder) == [home + "/.claude-acme", personal, globex])
    }
}

@Test func `without a home folder only the added folders are listed, missing or not`() {
    let added = ["/DontBurnCoreTests-\(UUID().uuidString)/.claude-acme"]

    #expect(ClaudeProfile.find(inHome: nil, added: added, allowedFolder: nil).map(\.folder) == added)
}

@Test func `a settings file is resolved through its link inside the allowed folder`() throws {
    try withTemporaryFolder { temporary in
        let home = try madeUpHome(temporary)
        try temporary.make("home/shared")
        let shared = temporary.path("home/shared/settings.json")
        try Data().write(to: URL(filePath: shared))
        try FileManager.default.createSymbolicLink(
            atPath: home + "/.claude-acme/settings.json",
            withDestinationPath: "../shared/settings.json",
        )

        let profiles = ClaudeProfile.find(inHome: home, added: [], allowedFolder: home)
        let acme = try #require(profiles.first { $0.name == ".claude-acme" })
        let globex = try #require(profiles.first { $0.name == ".claude-globex" })

        #expect(acme.settingsFile == FolderPath.resolved(shared))
        #expect(globex.settingsFile == FolderPath.resolved(home) + "/.claude-globex/settings.json")
    }
}

@Test func `a settings file outside the allowed folder, or with none, is not resolved`() throws {
    try withTemporaryFolder { temporary in
        let home = try madeUpHome(temporary)
        let outside = try temporary.make("elsewhere") + "/settings.json"
        try Data().write(to: URL(filePath: outside))
        let link = home + "/.claude-acme/settings.json"
        try FileManager.default.createSymbolicLink(atPath: link, withDestinationPath: outside)
        let added = try temporary.make("work/.claude-personal")

        let inStandIn = ClaudeProfile.find(inHome: home, added: [added], allowedFolder: home)
        let inNone = ClaudeProfile.find(inHome: home, added: [added], allowedFolder: nil)

        #expect(inStandIn.first { $0.name == ".claude-acme" }?.settingsFile == nil)
        #expect(inStandIn.first { $0.folder == added }?.settingsFile == nil)
        #expect(inNone.allSatisfy { $0.settingsFile == nil })
    }
}

@Test func `profiles that resolve to one settings file share it, and no others do`() {
    let shared = "/tmp/acme-globex/settings.json"
    let acme = ClaudeProfile(folder: "/home/.claude-acme", settingsFile: shared)
    let globex = ClaudeProfile(folder: "/home/.claude-globex", settingsFile: shared)
    let personal = ClaudeProfile(folder: "/home/.claude-personal", settingsFile: "/home/.claude-personal/settings.json")
    let unknownA = ClaudeProfile(folder: "/work/a", settingsFile: nil)
    let unknownB = ClaudeProfile(folder: "/work/b", settingsFile: nil)
    let all = [acme, globex, personal, unknownA, unknownB]

    #expect(acme.sharers(among: all) == [globex])
    #expect(globex.sharers(among: all) == [acme])
    #expect(personal.sharers(among: all).isEmpty)
    #expect(unknownA.sharers(among: all).isEmpty)
}
