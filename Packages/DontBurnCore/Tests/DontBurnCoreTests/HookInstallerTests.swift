@testable import DontBurnCore
import Foundation
import Testing

// MARK: - Install, then uninstall, byte for byte

@Test(arguments: SettingsSample.installable)
func `install then uninstall gives back the settings file byte for byte`(original: Data) throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: original)

        try desk.install(file)
        #expect(try desk.read(file) != original)
        #expect(desk.installer.status(ofSettingsFile: file) == .installed)
        let result = try desk.installer.uninstall(settingsFile: file)

        #expect(try desk.read(file) == original)
        #expect(result.isIdentical)
        #expect(result.differingKeys.isEmpty)
        #expect(!result.wasReplaced)
        #expect(result.keptBackup == nil)
        #expect(desk.records.isEmpty)
        #expect(desk.installer.status(ofSettingsFile: file) == .notInstalled)
    }
}

@Test func `a symlinked file shared by two profiles is installed once, through its target, and comes back`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let shared = try desk.profile("shared", settings: SettingsSample.otherHook)
        let acme = try desk.profile(".claude-acme", linkingTo: "../shared/settings.json")
        let globex = try desk.profile(".claude-globex", linkingTo: shared)

        let plan = try desk.install(acme)

        #expect(plan.settingsFile == FolderPath.resolved(shared))
        #expect(desk.installer.status(ofSettingsFile: acme) == .installed)
        #expect(desk.installer.status(ofSettingsFile: globex) == .installed)
        #expect(desk.installer.status(ofSettingsFile: shared) == .installed)
        #expect(throws: HookInstallError.alreadyInstalled) { try desk.installer.plan(forSettingsFile: globex) }
        #expect(try SettingsSample.hooks(running: desk.command, in: desk.read(shared)) == HookEvent.handledNames.count)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: acme) == "../shared/settings.json")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: globex) == shared)

        let result = try desk.installer.uninstall(settingsFile: globex)

        #expect(result.isIdentical)
        #expect(try desk.read(shared) == SettingsSample.otherHook)
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: acme) == "../shared/settings.json")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: globex) == shared)
        #expect(desk.installer.status(ofSettingsFile: acme) == .notInstalled)
        #expect(desk.records.isEmpty)
    }
}

@Test func `the release and dev commands are what the file runs`() throws {
    try withTemporaryFolder { temporary in
        let release = try HookDesk(temporary)
        let dev = try HookInstaller(
            command: HookCommand(toolPath: release.tool, target: .dev),
            directory: temporary.url.appending(path: "support-dev"),
            allowedFolder: temporary.path("home"),
        )
        let acme = try release.profile(".claude-acme", settings: SettingsSample.emptyObject)
        let globex = try release.profile(".claude-globex", settings: SettingsSample.emptyObject)

        try release.install(acme)
        try dev.install(dev.plan(forSettingsFile: globex))

        #expect(try Set(HookSettings.commands(in: release.read(acme))) == ["'\(release.tool)'"])
        #expect(try Set(HookSettings.commands(in: release.read(globex))) == ["'\(release.tool)' --target dev"])
    }
}

@Test func `the root as the allowed folder reaches any file, as in the Release build`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary, allowedFolder: "/")
        let file = try desk.profile(".claude-personal", settings: SettingsSample.otherHook)

        try desk.install(file)
        let result = try desk.installer.uninstall(settingsFile: file)

        #expect(result.isIdentical)
        #expect(try desk.read(file) == SettingsSample.otherHook)
    }
}

@Test func `install keeps the file's mode and leaves nothing but the settings file in the profile`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: file)

        try desk.install(file)

        #expect(try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int == 0o600)
        #expect(try desk.files(in: ".claude-acme") == ["settings.json"])
        #expect(desk.records.count == 2)
        #expect(desk.records.contains { $0.hasSuffix(".backup") })
        #expect(desk.records.contains { $0.hasSuffix(".json") })

        _ = try desk.installer.uninstall(settingsFile: file)

        #expect(try FileManager.default.attributesOfItem(atPath: file)[.posixPermissions] as? Int == 0o600)
        #expect(try desk.files(in: ".claude-acme") == ["settings.json"])
    }
}

@Test func `the record names the real file, the inode the install left and what it created`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)

        try desk.install(file)
        let name = try #require(desk.records.first { $0.hasSuffix(".json") })
        let record = try JSONDecoder().decode(
            HookInstallRecord.self,
            from: desk.read(temporary.path("support/HookInstalls/\(name)")),
        )

        #expect(record.settingsFile == FolderPath.resolved(file))
        #expect(try record.inode == desk.inode(file))
        #expect(record.command == desk.command)
        #expect(!record.createdHooks)
        #expect(record.createdEvents == HookEvent.handledNames.filter { $0 != "Stop" })
        #expect(!record.wasEmpty)
    }
}

// MARK: - The plan shown before writing

@Test(arguments: SettingsSample.installable)
func `the changed lines take the old text to the new one`(original: Data) throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let plan = try desk.installer.plan(forSettingsFile: desk.profile(".claude-acme", settings: original))
        func lines(_ data: Data) -> [String] {
            let text = SettingsSample.text(data)
            return text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
        let old = lines(original)
        let new = lines(plan.edit.data)
        let changes = plan.changedLines
        let removed = Set(changes.filter { $0.kind == .removed }.map(\.number))
        let added = Set(changes.filter { $0.kind == .added }.map(\.number))

        for change in changes {
            #expect((change.kind == .added ? new : old)[change.number - 1] == change.text)
        }
        let kept = old.indices.filter { !removed.contains($0 + 1) }.map { old[$0] }
        #expect(kept == new.indices.filter { !added.contains($0 + 1) }.map { new[$0] })
        #expect(changes.count == removed.count + added.count)
        #expect(changes.contains { $0.text.contains(desk.command.replacing("'", with: "")) })
    }
}

@Test func `a plan writes nothing`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)

        let plan = try desk.installer.plan(forSettingsFile: file)

        #expect(plan.original == SettingsSample.otherHook)
        #expect(try desk.read(file) == SettingsSample.otherHook)
        #expect(desk.records.isEmpty)
    }
}

@Test func `a file of zero bytes shows every line as added`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let plan = try desk.installer.plan(forSettingsFile: desk.profile(".claude-acme", settings: Data()))
        let lineCount = SettingsSample.text(plan.edit.data).split(separator: "\n").count

        #expect(plan.changedLines.map(\.number) == Array(1 ... lineCount))
        #expect(plan.changedLines.allSatisfy { $0.kind == .added })
    }
}

// MARK: - Installing twice

@Test func `installing twice changes nothing the second time, and the first backup is kept`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        let plan = try desk.install(file)
        let installed = try desk.read(file)
        let records = desk.records
        let backupName = try #require(records.first { $0.hasSuffix(".backup") })
        let backup = try desk.read(temporary.path("support/HookInstalls/\(backupName)"))

        #expect(throws: HookInstallError.alreadyInstalled) { try desk.installer.plan(forSettingsFile: file) }
        #expect(throws: HookInstallError.alreadyInstalled) { try desk.installer.install(plan) }

        #expect(try desk.read(file) == installed)
        #expect(desk.records == records)
        #expect(backup == SettingsSample.otherHook)
        #expect(try desk.installer.uninstall(settingsFile: file).isIdentical)
        #expect(try desk.read(file) == SettingsSample.otherHook)
    }
}

@Test func `a second installer with another command finds the first install and refuses`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        let installed = try desk.read(file)
        let other = try HookInstaller(
            command: HookCommand(toolPath: desk.tool, target: .dev),
            directory: temporary.url.appending(path: "support-other"),
            allowedFolder: temporary.path("home"),
        )

        #expect(other.status(ofSettingsFile: file) == .foundWithoutRecord)
        #expect(throws: HookInstallError.alreadyInstalled) { try other.plan(forSettingsFile: file) }
        #expect(throws: HookInstallError.notInstalled) { try other.uninstall(settingsFile: file) }
        #expect(try desk.read(file) == installed)
    }
}

@Test func `a hook added by hand shows as found, and is neither installed over nor removed`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let byHand = Data((HookSettings.manualLines(command: desk.command) + "\n").utf8)
        let file = try desk.profile(".claude-acme", settings: byHand)

        #expect(desk.installer.status(ofSettingsFile: file) == .foundWithoutRecord)
        #expect(throws: HookInstallError.alreadyInstalled) { try desk.installer.plan(forSettingsFile: file) }
        #expect(throws: HookInstallError.notInstalled) { try desk.installer.uninstall(settingsFile: file) }
        #expect(try desk.read(file) == byHand)
        #expect(desk.records.isEmpty)
    }
}
