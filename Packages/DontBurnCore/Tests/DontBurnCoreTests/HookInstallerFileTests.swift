@testable import DontBurnCore
import Foundation
import Testing

private func permissions(_ path: String) throws -> Int {
    try #require(FileManager.default.attributesOfItem(atPath: path)[.posixPermissions] as? Int)
}

// MARK: - New files

@Test func `a new file is written whole, takes its mode, and is never written over a file already there`() throws {
    try withTemporaryFolder { temporary in
        let path = temporary.path("record.json")
        let data = Data(repeating: UInt8(ascii: "a"), count: HookSettings.maximumSize)

        let inode = try writeNewFile(data, at: path, mode: 0o644)

        #expect(try Data(contentsOf: URL(filePath: path)) == data)
        #expect(try permissions(path) == 0o644)
        #expect(try FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? UInt64 == inode)

        #expect(throws: HookInstallError.writeFailed) { try writeNewFile(Data("{}".utf8), at: path, mode: 0o600) }

        #expect(try Data(contentsOf: URL(filePath: path)) == data)
        #expect(try permissions(path) == 0o644)
    }
}

@Test(arguments: [0o600, 0o644, 0o664])
func `the backup and the record are for this user alone, and the settings file keeps its mode`(mode: Int) throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try FileManager.default.setAttributes([.posixPermissions: mode], ofItemAtPath: file)

        try desk.install(file)

        #expect(try permissions(file) == mode)
        #expect(desk.records.count == 2)
        for name in desk.records {
            #expect(try permissions(temporary.path("support/HookInstalls/\(name)")) == 0o600, "\(name)")
        }

        let changed = try SettingsSample.setting("model", to: .string("sonnet"), in: desk.read(file))
        try changed.write(to: URL(filePath: file))
        let result = try desk.installer.uninstall(settingsFile: file)
        let backup = try #require(result.keptBackup)

        #expect(!result.isIdentical)
        #expect(desk.records == [(backup as NSString).lastPathComponent])
        #expect(try permissions(backup) == 0o600)
        #expect(try desk.read(backup) == SettingsSample.otherHook)
        #expect(try permissions(file) == mode)
        #expect(try desk.files(in: ".claude-acme") == ["settings.json"])
    }
}

// MARK: - Hard links

@Test func `a settings file with a second hard link is refused by its every name, and is still read`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        let second = try temporary.make("home/.claude-globex") + "/settings.json"
        try FileManager.default.linkItem(atPath: file, toPath: second)
        let inode = try desk.inode(file)
        let byHand = Data((HookSettings.manualLines(command: desk.command) + "\n").utf8)
        let found = try desk.profile(".claude-personal", settings: byHand)
        try FileManager.default.linkItem(atPath: found, toPath: temporary.path("home/settings-copy.json"))

        #expect(desk.installer.status(ofSettingsFile: file) == .notInstalled)
        #expect(desk.installer.status(ofSettingsFile: found) == .foundWithoutRecord)
        #expect(throws: HookInstallError.hardLinked) { try desk.installer.plan(forSettingsFile: file) }
        #expect(throws: HookInstallError.hardLinked) { try desk.installer.plan(forSettingsFile: second) }

        #expect(try desk.read(file) == SettingsSample.otherHook)
        #expect(try desk.inode(file) == inode)
        #expect(try desk.inode(second) == inode)
        #expect(try desk.files(in: ".claude-acme") == ["settings.json"])
        #expect(desk.records.isEmpty)
    }
}

@Test func `an install refuses a file that gained a hard link after the plan was shown`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        let plan = try desk.installer.plan(forSettingsFile: file)
        let second = try temporary.make("elsewhere") + "/settings.json"
        try FileManager.default.linkItem(atPath: file, toPath: second)

        #expect(throws: HookInstallError.hardLinked) { try desk.installer.install(plan) }

        #expect(try desk.read(file) == SettingsSample.otherHook)
        #expect(try desk.inode(file) == desk.inode(second))
        #expect(try desk.files(in: ".claude-acme") == ["settings.json"])
        #expect(desk.records.isEmpty)
    }
}

@Test func `an uninstall refuses a file that gained a hard link after the install, and keeps the record`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        let installed = try desk.read(file)
        let records = desk.records
        let second = try temporary.make("elsewhere") + "/settings.json"
        try FileManager.default.linkItem(atPath: file, toPath: second)
        let inode = try desk.inode(file)

        #expect(throws: HookInstallError.hardLinked) { try desk.installer.uninstall(settingsFile: file) }

        #expect(try desk.read(file) == installed)
        #expect(try desk.inode(file) == inode)
        #expect(try desk.inode(second) == inode)
        #expect(try desk.files(in: ".claude-acme") == ["settings.json"])
        #expect(desk.records == records)
        #expect(desk.installer.status(ofSettingsFile: file) == .installed)

        try FileManager.default.removeItem(atPath: second)
        #expect(try desk.installer.uninstall(settingsFile: file).isIdentical)
        #expect(try desk.read(file) == SettingsSample.otherHook)
    }
}

// MARK: - Only the events the install writes to

@Test func `uninstall leaves the recorded command's group under an event the install does not write to`() throws {
    try withTemporaryFolder { temporary in
        let desk = try HookDesk(temporary)
        let file = try desk.profile(".claude-acme", settings: SettingsSample.otherHook)
        try desk.install(file)
        var members = try #require(JSONValue(parsing: desk.read(file)).members)
        var hooks = try #require(members["hooks"]?.members)
        hooks["PreToolUse"] = .array([HookSettings.group(command: desk.command)])
        members["hooks"] = .object(hooks)
        try Data((JSONValue.object(members).formatted + "\n").utf8).write(to: URL(filePath: file))

        let result = try desk.installer.uninstall(settingsFile: file)
        let after = try desk.read(file)
        let left = try #require(JSONValue(parsing: after).members?["hooks"]?.members)

        #expect(!result.isIdentical)
        #expect(!result.wasReplaced)
        #expect(result.differingKeys == ["hooks"])
        #expect(result.keptBackup != nil)
        #expect(left.map(\.key) == ["Stop", "PreToolUse"])
        #expect(left["PreToolUse"] == .array([HookSettings.group(command: desk.command)]))
        #expect(HookSettings.commands(in: after) == ["~/bin/acme-notify", desk.command])
    }
}
