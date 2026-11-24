@testable import DontBurnCore
import Foundation
import Testing

/// An installer that works only inside a temporary folder: a stand-in tool in
/// `app`, the profiles in `home`, and the app's own folder in `support`.
struct HookDesk {
    let folder: TemporaryFolder
    let tool: String
    let installer: HookInstaller

    init(_ folder: TemporaryFolder, allowedFolder: String? = nil) throws {
        self.folder = folder
        try folder.make("app")
        try folder.make("home")
        tool = folder.path("app/dontburn-hook")
        let made = FileManager.default.createFile(
            atPath: tool,
            contents: Data("#!/bin/sh\nexit 0\n".utf8),
            attributes: [.posixPermissions: 0o755],
        )
        try #require(made)
        installer = try HookInstaller(
            command: HookCommand(toolPath: tool, target: .release),
            directory: folder.url.appending(path: "support"),
            allowedFolder: allowedFolder ?? folder.path("home"),
        )
    }

    var command: String {
        installer.command.text
    }

    /// The settings file of the profile `name`, written with `data`.
    @discardableResult
    func profile(_ name: String, settings data: Data) throws -> String {
        let file = try folder.make("home/\(name)") + "/settings.json"
        try data.write(to: URL(filePath: file))
        return file
    }

    /// The profile `name`, whose settings file links to `target`.
    @discardableResult
    func profile(_ name: String, linkingTo target: String) throws -> String {
        let file = try folder.make("home/\(name)") + "/settings.json"
        try FileManager.default.createSymbolicLink(atPath: file, withDestinationPath: target)
        return file
    }

    /// The names of the records and backups in the app's own folder.
    var records: [String] {
        // No folder yet means no record yet.
        let names = try? FileManager.default.contentsOfDirectory(atPath: folder.path("support/HookInstalls"))
        return (names ?? []).sorted()
    }

    /// The names of the files in the profile `name`.
    func files(in name: String) throws -> [String] {
        try FileManager.default.contentsOfDirectory(atPath: folder.path("home/\(name)")).sorted()
    }

    func read(_ path: String) throws -> Data {
        try Data(contentsOf: URL(filePath: path))
    }

    func inode(_ path: String) throws -> UInt64 {
        try #require(FileManager.default.attributesOfItem(atPath: path)[.systemFileNumber] as? UInt64)
    }

    /// Installs through the plan the user would confirm.
    @discardableResult
    func install(_ path: String) throws -> HookInstallPlan {
        let plan = try installer.plan(forSettingsFile: path)
        try installer.install(plan)
        return plan
    }
}

/// `data` written to `path` by a new file renamed over it, as an app that
/// writes atomically does.
func replace(_ path: String, with data: Data) throws {
    let staged = path + ".new"
    try data.write(to: URL(filePath: staged))
    try #require(rename(staged, path) == 0)
}
