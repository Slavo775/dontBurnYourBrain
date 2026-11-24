import Foundation

/// Whether the hook is in a settings file.
public enum HookStatus: Equatable, Sendable {
    /// Neither installed nor found.
    case notInstalled
    /// Installed by this app, and on record, so it can be uninstalled.
    case installed
    /// A hook of this app's tool is in the file, but no install of it is on
    /// record, as when it was added by hand. It is removed by hand too.
    case foundWithoutRecord
    /// The file lies outside the folder this build may read, so it was never looked at.
    case outOfReach
}

/// One line that an install adds to a settings file or takes from it.
public struct ChangedLine: Equatable, Sendable {
    /// Whether the line is added or taken out.
    public enum Kind: Equatable, Sendable {
        /// The line is new.
        case added
        /// The line goes.
        case removed
    }

    /// Added or removed.
    public let kind: Kind
    /// The line's number, from 1: in the new text for an added line, in the old one for a removed line.
    public let number: Int
    /// The line, without its newline.
    public let text: String
}

/// An install shown to the user before it is written.
public struct HookInstallPlan: Equatable, Sendable {
    /// The real path of the settings file, with every symlink resolved.
    public let settingsFile: String
    /// The file's bytes as they were read.
    public let original: Data
    /// The new bytes and what the install creates.
    public let edit: HookSettingsEdit

    /// The lines that change, in the order of the file: every line removed
    /// and every line added, as the shortest line diff finds them.
    public var changedLines: [ChangedLine] {
        func lines(_ data: Data) -> [String] {
            // Both texts passed the round trip, so both are valid UTF-8.
            let text = String(validating: data, as: UTF8.self) ?? ""
            return text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        }
        let old = lines(original)
        let new = lines(edit.data)
        var removed: [Int: String] = [:]
        var inserted: [Int: String] = [:]
        for change in new.difference(from: old) {
            switch change {
            case let .remove(offset, line, _): removed[offset] = line
            case let .insert(offset, line, _): inserted[offset] = line
            }
        }
        var changes: [ChangedLine] = []
        var oldIndex = 0
        var newIndex = 0
        while oldIndex < old.count || newIndex < new.count {
            if let line = removed[oldIndex] {
                changes.append(ChangedLine(kind: .removed, number: oldIndex + 1, text: line))
                oldIndex += 1
            } else if let line = inserted[newIndex] {
                changes.append(ChangedLine(kind: .added, number: newIndex + 1, text: line))
                newIndex += 1
            } else {
                oldIndex += 1
                newIndex += 1
            }
        }
        return changes
    }
}

/// What an uninstall left.
public struct HookUninstallResult: Equatable, Sendable {
    /// Whether the settings file is byte for byte what it was before the install.
    public let isIdentical: Bool
    /// The top-level keys whose value differs from before the install.
    /// Empty when the file is identical, or differs only in order or formatting.
    public let differingKeys: [String]
    /// Whether another file stands at the path since the install, as when an
    /// app wrote the settings by replacing the file.
    public let wasReplaced: Bool
    /// The path of the backup from before the install, kept when the file
    /// differs from it, or `nil` when it was removed.
    public let keptBackup: String?
}

/// What one install changed, kept in the app's own folder for its uninstall.
public struct HookInstallRecord: Codable, Equatable, Sendable {
    /// The real path of the settings file.
    public var settingsFile: String
    /// The inode of the file the install left.
    public var inode: UInt64
    /// The command the install wrote.
    public var command: String
    /// Whether the install added the `hooks` key.
    public var createdHooks: Bool
    /// The event lists the install added.
    public var createdEvents: [String]
    /// Whether the file had zero bytes before the install.
    public var wasEmpty: Bool
}

/// Installs the hook into Claude Code settings files and removes it again.
///
/// Every file it touches is resolved to its real path first, so a symlinked
/// `settings.json` has its target written and the link is never replaced.
/// It writes atomically: a new file beside the target, flushed to the disk
/// with the target's mode, renamed over it. A file with more than one hard
/// link is refused, since the rename would split it. Its records and the
/// backups live in ``folderName`` inside `directory`, the app's own folder,
/// never in a profile, readable by this user alone. A backup is never
/// overwritten and never written back.
public struct HookInstaller: Sendable {
    /// The folder inside the app's own folder that holds the records and the backups.
    public static let folderName = "HookInstalls"

    /// The command written into a settings file.
    public let command: HookCommand
    private let records: URL
    private let scope: SettingsScope

    /// An installer that writes `command`, keeps its records in `directory`,
    /// the app's own folder, and touches only files inside `allowedFolder`.
    ///
    /// `allowedFolder` is `/` for the Release build, the stand-in folder for
    /// the Dev build, and `nil` for a Dev build without one, which may touch no file.
    public init(command: HookCommand, directory: URL, allowedFolder: String?) {
        self.command = command
        records = directory.appending(path: Self.folderName, directoryHint: .isDirectory)
        scope = SettingsScope(allowedFolder)
    }

    /// Whether the hook is in the settings file at `path`, in any spelling.
    ///
    /// A file outside the allowed folder is ``HookStatus/outOfReach`` and is
    /// never read. One that cannot be read counts as not installed, and
    /// ``plan(forSettingsFile:)`` then says why.
    public func status(ofSettingsFile path: String) -> HookStatus {
        guard let path = scope.resolve(path) else { return .outOfReach }
        if record(for: path) != nil {
            return .installed
        }
        // A file that cannot be read shows as not installed. Install then names the reason.
        guard let file = try? SettingsFile(path: path) else { return .notInstalled }
        let isFound = HookSettings.commands(in: file.data).contains { $0.contains(command.toolName) }
        return isFound ? .foundWithoutRecord : .notInstalled
    }

    /// The install into the settings file at `path`, for the user to confirm. Writes nothing.
    ///
    /// Throws ``HookInstallError/outsideAllowedFolder``,
    /// ``HookInstallError/toolMissing`` when the command's tool is not an
    /// executable file, ``HookInstallError/alreadyInstalled`` when an install
    /// into the file is on record, ``HookInstallError/hardLinked``, the
    /// errors of reading it, and those of
    /// ``HookSettings/installing(command:marker:into:)``.
    public func plan(forSettingsFile path: String) throws -> HookInstallPlan {
        guard let path = scope.resolve(path) else { throw HookInstallError.outsideAllowedFolder }
        guard FileManager.default.isExecutableFile(atPath: command.toolPath) else { throw HookInstallError.toolMissing }
        guard record(for: path) == nil else { throw HookInstallError.alreadyInstalled }
        let file = try SettingsFile.writable(path)
        let edit = try HookSettings.installing(command: command.text, marker: command.toolName, into: file.data)
        return HookInstallPlan(settingsFile: path, original: file.data, edit: edit)
    }

    /// Writes `plan`, which the user confirmed.
    ///
    /// Keeps a backup and a record first, then renames the new file over the
    /// settings file. Throws ``HookInstallError/changedMeanwhile`` when the
    /// file no longer holds what the plan read, and
    /// ``HookInstallError/writeFailed`` when a file cannot be written. Either
    /// way the settings file is unchanged, and the backup and record are gone.
    public func install(_ plan: HookInstallPlan) throws {
        guard let path = scope.resolve(plan.settingsFile) else { throw HookInstallError.outsideAllowedFolder }
        guard FileManager.default.isExecutableFile(atPath: command.toolPath) else { throw HookInstallError.toolMissing }
        guard record(for: path) == nil else { throw HookInstallError.alreadyInstalled }
        let file = try SettingsFile.writable(path)
        guard file.data == plan.original else { throw HookInstallError.changedMeanwhile }
        let id = UUID().uuidString
        let staged = try file.stage(plan.edit.data)
        do {
            try FileManager.default.createDirectory(at: records, withIntermediateDirectories: true)
            // The settings can hold tokens in `env`, so only this user may read the backup.
            _ = try writeNewFile(plan.original, at: backup(id).path(percentEncoded: false), mode: 0o600)
            let record = HookInstallRecord(
                settingsFile: path,
                inode: staged.inode,
                command: command.text,
                createdHooks: plan.edit.createdHooks,
                createdEvents: plan.edit.createdEvents,
                wasEmpty: plan.edit.wasEmpty,
            )
            _ = try writeNewFile(
                JSONEncoder().encode(record), at: recordFile(id).path(percentEncoded: false), mode: 0o600,
            )
            try file.replace(with: staged)
        } catch {
            unlink(staged.path)
            // Both files were made under a new name just now, so only this install's own go.
            try? FileManager.default.removeItem(at: recordFile(id))
            try? FileManager.default.removeItem(at: backup(id))
            throw error as? HookInstallError ?? .writeFailed
        }
    }

    /// Removes the hook the recorded install put into the settings file at `path`.
    ///
    /// Takes out only the groups whose command is the recorded one, from the
    /// lists of the events the install writes to, then only the containers
    /// the install created, and keeps every other change. When
    /// another file stands at the path since the install, its own groups are
    /// taken out all the same, and the result says so. Then compares the file
    /// with the backup. The backup is never written back. The record goes,
    /// and the backup too unless the file differs from it.
    ///
    /// Throws ``HookInstallError/notInstalled`` when no install into the file
    /// is on record, ``HookInstallError/hardLinked``, and the errors of
    /// reading and checking it, which keep the record.
    public func uninstall(settingsFile path: String) throws -> HookUninstallResult {
        guard let path = scope.resolve(path) else { throw HookInstallError.outsideAllowedFolder }
        guard let found = record(for: path) else { throw HookInstallError.notInstalled }
        let id = found.id
        let file = try SettingsFile.writable(path)
        let updated = try HookSettings.uninstalling(
            command: found.record.command,
            createdHooks: found.record.createdHooks,
            createdEvents: found.record.createdEvents,
            wasEmpty: found.record.wasEmpty,
            from: file.data,
        )
        if updated != file.data {
            let staged = try file.stage(updated)
            do {
                try file.replace(with: staged)
            } catch {
                unlink(staged.path)
                throw error
            }
        }
        // A backup that cannot be read can only be reported as a difference.
        let before = try? Data(contentsOf: backup(id))
        let isIdentical = before == updated
        try? FileManager.default.removeItem(at: recordFile(id)) // An install no longer in the file.
        if isIdentical {
            try? FileManager.default.removeItem(at: backup(id)) // Identical to the file, so nothing is lost.
        }
        return HookUninstallResult(
            isIdentical: isIdentical,
            differingKeys: before.flatMap { HookSettings.differingKeys(updated, from: $0) } ?? [],
            wasReplaced: file.inode != found.record.inode,
            keptBackup: isIdentical ? nil : backup(id).path(percentEncoded: false),
        )
    }

    private func record(for path: String) -> (id: String, record: HookInstallRecord)? {
        // No folder yet means no install yet.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: records.path(percentEncoded: false))) ?? []
        for name in names.sorted() where name.hasSuffix(".json") {
            let id = String(name.dropLast(".json".count))
            // A record that cannot be read names no file.
            guard let data = try? Data(contentsOf: recordFile(id)),
                  let record = try? JSONDecoder().decode(HookInstallRecord.self, from: data),
                  record.settingsFile == path
            else { continue }
            return (id, record)
        }
        return nil
    }

    private func recordFile(_ id: String) -> URL {
        records.appending(path: "\(id).json", directoryHint: .notDirectory)
    }

    private func backup(_ id: String) -> URL {
        records.appending(path: "\(id).backup", directoryHint: .notDirectory)
    }
}
