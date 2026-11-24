@testable import DontBurnCore
import Foundation
import Testing

// MARK: - The two faults of the spike's first review

@Test func `a settings file that is no longer JSON is never emptied by the uninstall`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        let broken = Data("not json\n".utf8)
        try broken.write(to: URL(filePath: file))
        let records = desk.records

        #expect(throws: HookInstallError.notJSONObject) { try desk.installer.uninstall(settingsFile: file) }

        #expect(try desk.read(file) == broken)
        #expect(desk.records == records)
        #expect(desk.installer.status(ofSettingsFile: file) == .installed)
    }
}

@Test func `a record that cannot be read leaves the file as it is`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        let installed = try desk.read(file)
        let name = try #require(desk.records.first { $0.hasSuffix(".json") })
        try Data("not json".utf8).write(to: URL(filePath: temporary.path("support/HookInstalls/\(name)")))

        #expect(throws: HookInstallError.notInstalled) { try desk.installer.uninstall(settingsFile: file) }
        #expect(try desk.read(file) == installed)
    }
}

@Test func `an uninstall that cannot write leaves the file as it was and keeps the record`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        let installed = try desk.read(file)
        let profile = temporary.path("home/.claude-acme")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: profile)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: profile) }

        #expect(throws: HookInstallError.writeFailed) { try desk.installer.uninstall(settingsFile: file) }

        #expect(try desk.read(file) == installed)
        #expect(desk.records.count == 2)
        #expect(try FileManager.default.contentsOfDirectory(atPath: profile) == ["settings.json"])
    }
}

@Test func `an install whose backup cannot be written leaves the file as it was`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        let support = try temporary.make("support")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: support)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: support) }

        #expect(throws: HookInstallError.writeFailed) { try desk.install(file) }

        #expect(try desk.read(file) == SettingsSample.otherHook)
        #expect(try desk.files(in: ".claude-acme") == ["settings.json"])
        #expect(desk.installer.status(ofSettingsFile: file) == .notInstalled)
    }
}

@Test func `an install whose new file cannot be written leaves no record`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        let plan = try desk.installer.plan(forSettingsFile: file)
        let profile = temporary.path("home/.claude-acme")
        try FileManager.default.setAttributes([.posixPermissions: 0o555], ofItemAtPath: profile)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: profile) }

        #expect(throws: HookInstallError.writeFailed) { try desk.installer.install(plan) }

        #expect(try desk.read(file) == SettingsSample.otherHook)
        #expect(desk.records.isEmpty)
    }
}

@Test func `the backup is never written back over a change made while installed`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        let changed = try SettingsSample.setting("model", to: .string("sonnet"), in: desk.read(file))
        try changed.write(to: URL(filePath: file))

        let result = try desk.installer.uninstall(settingsFile: file)
        let after = try desk.read(file)

        #expect(!result.isIdentical)
        #expect(result.differingKeys == ["model"])
        #expect(!result.wasReplaced)
        #expect(try JSONValue(parsing: after).members?["model"] == .string("sonnet"))
        #expect(SettingsSample.hooks(running: desk.command, in: after) == 0)
        let backup = try #require(result.keptBackup)
        #expect(try desk.read(backup) == SettingsSample.otherHook)
        #expect(desk.records == [(backup as NSString).lastPathComponent])
        #expect(desk.installer.status(ofSettingsFile: file) == .notInstalled)
    }
}

// MARK: - A file replaced while installed

@Test func `a file replaced while installed loses only the app's groups and the result says it was replaced`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        let installedInode = try desk.inode(file)
        try replace(file, with: SettingsSample.setting("model", to: .string("sonnet"), in: desk.read(file)))
        try #require(try desk.inode(file) != installedInode)

        let result = try desk.installer.uninstall(settingsFile: file)
        let after = try desk.read(file)

        #expect(result.wasReplaced)
        #expect(!result.isIdentical)
        #expect(result.differingKeys == ["model"])
        #expect(result.keptBackup != nil)
        #expect(SettingsSample.hooks(running: desk.command, in: after) == 0)
        #expect(HookSettings.commands(in: after) == ["~/bin/acme-notify"])
    }
}

@Test func `a file replaced by the same bytes still comes back identical`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        try replace(file, with: desk.read(file))

        let result = try desk.installer.uninstall(settingsFile: file)

        #expect(result.wasReplaced)
        #expect(result.isIdentical)
        #expect(result.keptBackup == nil)
        #expect(try desk.read(file) == SettingsSample.otherHook)
    }
}

@Test func `a file whose groups were all taken out by hand is not written, and the backup is kept`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        let byHand = try SettingsSample.setting("theme", to: .string("dark"), in: SettingsSample.otherHook)
        try byHand.write(to: URL(filePath: file))
        let inode = try desk.inode(file)

        let result = try desk.installer.uninstall(settingsFile: file)

        #expect(try desk.read(file) == byHand)
        #expect(try desk.inode(file) == inode)
        #expect(!result.isIdentical)
        #expect(result.differingKeys == ["theme"])
        #expect(result.keptBackup != nil)
    }
}

// MARK: - Changed while the user looked

@Test func `a file changed after the plan was shown is not written`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        let plan = try desk.installer.plan(forSettingsFile: file)
        let changed = try SettingsSample.setting("model", to: .string("sonnet"), in: SettingsSample.otherHook)
        try changed.write(to: URL(filePath: file))

        #expect(throws: HookInstallError.changedMeanwhile) { try desk.installer.install(plan) }

        #expect(try desk.read(file) == changed)
        #expect(desk.records.isEmpty)
        #expect(try desk.files(in: ".claude-acme") == ["settings.json"])
    }
}

// MARK: - Refusals

@Test(arguments: [
    (SettingsSample.handFormatted, HookInstallError.unusualFormatting),
    (SettingsSample.hooksList, .hooksNotObjectOfLists),
    (SettingsSample.hooksNull, .hooksNotObjectOfLists),
    (SettingsSample.lines("[]"), .notJSONObject),
])
func `a file the installer may not edit is refused and left as it is`(data: Data, error: HookInstallError) throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-personal", settings: data)

        #expect(desk.installer.status(ofSettingsFile: file) == .notInstalled)
        #expect(throws: error) { try desk.installer.plan(forSettingsFile: file) }
        #expect(try desk.read(file) == data)
        #expect(desk.records.isEmpty)
    }
}

@Test func `a missing settings file, a folder in its place and a file too large are refused`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let missing = try temporary.make("home/.claude-acme") + "/settings.json"
        let folder = try temporary.make("home/.claude-globex/settings.json")
        let large = try desk.profile(
            ".claude-personal",
            settings: Data(repeating: UInt8(ascii: " "), count: HookSettings.maximumSize + 1),
        )

        #expect(desk.installer.status(ofSettingsFile: missing) == .notInstalled)
        #expect(throws: HookInstallError.missing) { try desk.installer.plan(forSettingsFile: missing) }
        #expect(throws: HookInstallError.notAFile) { try desk.installer.plan(forSettingsFile: folder) }
        #expect(throws: HookInstallError.tooLarge) { try desk.installer.plan(forSettingsFile: large) }
        #expect(!FileManager.default.fileExists(atPath: missing))
    }
}

@Test func `a settings file that cannot be read is refused and shows as not installed`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: file)
        defer { try? FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: file) }

        #expect(desk.installer.status(ofSettingsFile: file) == .notInstalled)
        #expect(throws: HookInstallError.unreadable) { try desk.installer.plan(forSettingsFile: file) }
    }
}

@Test func `without an executable tool nothing is planned or installed`() throws {
    try withTemporaryFolder { temporary in
        let ready = try HookDesk(temporary)
        let file = try ready.profile(".claude-acme", settings: SettingsSample.otherHook)
        let plan = try ready.installer.plan(forSettingsFile: file)
        try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: ready.tool)

        #expect(throws: HookInstallError.toolMissing) { try ready.installer.plan(forSettingsFile: file) }
        #expect(throws: HookInstallError.toolMissing) { try ready.installer.install(plan) }
        try FileManager.default.removeItem(atPath: ready.tool)
        #expect(throws: HookInstallError.toolMissing) { try ready.installer.install(plan) }
        #expect(try ready.read(file) == SettingsSample.otherHook)
    }
}

@Test func `uninstall without an install on record is refused and writes nothing`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)

        #expect(throws: HookInstallError.notInstalled) { try desk.installer.uninstall(settingsFile: file) }
        #expect(try desk.read(file) == SettingsSample.otherHook)
    }
}

@Test func `an uninstall refused because the file is gone keeps the record for a later try`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        let installed = try desk.read(file)
        try FileManager.default.removeItem(atPath: file)

        #expect(throws: HookInstallError.missing) { try desk.installer.uninstall(settingsFile: file) }
        #expect(desk.installer.status(ofSettingsFile: file) == .installed)

        try installed.write(to: URL(filePath: file))
        #expect(try desk.installer.uninstall(settingsFile: file).isIdentical)
        #expect(try desk.read(file) == SettingsSample.otherHook)
    }
}

// MARK: - The allowed folder

@Test func `without an allowed folder no file is looked at or changed`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let none = HookInstaller(command: desk.installer.command, directory: temporary.url, allowedFolder: nil)
        let relative = HookInstaller(command: desk.installer.command, directory: temporary.url, allowedFolder: "home")
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        let plan = try desk.installer.plan(forSettingsFile: file)

        for installer in [none, relative] {
            #expect(installer.status(ofSettingsFile: file) == .outOfReach)
            #expect(throws: HookInstallError.outsideAllowedFolder) { try installer.plan(forSettingsFile: file) }
            #expect(throws: HookInstallError.outsideAllowedFolder) { try installer.install(plan) }
            #expect(throws: HookInstallError.outsideAllowedFolder) { try installer.uninstall(settingsFile: file) }
        }
        #expect(try desk.read(file) == SettingsSample.otherHook)
    }
}

@Test func `a file outside the allowed folder, in any spelling, is out of reach`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let outside = try temporary.make("elsewhere/.claude-acme") + "/settings.json"
        try SettingsSample.otherHook.write(to: URL(filePath: outside))
        let spellings = [
            outside,
            temporary.path("home/../elsewhere/.claude-acme/settings.json"),
            temporary.path("home-other/settings.json"),
            "elsewhere/.claude-acme/settings.json",
            temporary.path("HOME/.claude-acme/settings.json"),
        ]

        for path in spellings {
            #expect(desk.installer.status(ofSettingsFile: path) == .outOfReach)
            #expect(throws: HookInstallError.outsideAllowedFolder) { try desk.installer.plan(forSettingsFile: path) }
        }
        #expect(try desk.read(outside) == SettingsSample.otherHook)
    }
}

@Test func `a link inside the allowed folder that points outside it is out of reach`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let outside = try temporary.make("elsewhere") + "/settings.json"
        try SettingsSample.otherHook.write(to: URL(filePath: outside))
        let link = try desk.profile(".claude-acme", linkingTo: outside)
        let folderLink = temporary.path("home/.claude-globex")
        try FileManager.default.createSymbolicLink(atPath: folderLink, withDestinationPath: temporary.path("elsewhere"))

        for path in [link, folderLink + "/settings.json"] {
            #expect(desk.installer.status(ofSettingsFile: path) == .outOfReach)
            #expect(throws: HookInstallError.outsideAllowedFolder) { try desk.installer.plan(forSettingsFile: path) }
            #expect(throws: HookInstallError.outsideAllowedFolder) { try desk.installer.uninstall(settingsFile: path) }
        }
        #expect(try desk.read(outside) == SettingsSample.otherHook)
    }
}

@Test func `the private spelling of the allowed folder reaches the same files`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        let other = FolderPath.resolved(file)
        try #require(other != file)

        let plan = try desk.installer.plan(forSettingsFile: other)

        #expect(plan.settingsFile == other)
    }
}
