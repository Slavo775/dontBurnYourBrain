import Foundation

// What the installer does to the text of a Claude Code settings file. Pure:
// bytes in, bytes out. The rules are "Rules for phase 3's installer" in
// docs/spikes/claude-hook.md.

/// Why the hook could not be installed or removed. Nothing was written.
public enum HookInstallError: Error, Equatable, Sendable {
    /// The profile has no `settings.json`.
    case missing
    /// The settings file is not a regular file, such as a folder.
    case notAFile
    /// The settings file could not be read.
    case unreadable
    /// The settings file is larger than ``HookSettings/maximumSize``.
    case tooLarge
    /// The settings file is not a JSON object.
    case notJSONObject
    /// Written two-space the way Claude Code writes it, the file would not
    /// come back byte for byte, so writing it would change more than the hook.
    case unusualFormatting
    /// `hooks` is not an object whose values are lists of groups.
    case hooksNotObjectOfLists
    /// The settings file has more than one hard link, which a write would
    /// split: the other name would keep the old text.
    case hardLinked
    /// The file holds the hook already, or an install of it is on record.
    case alreadyInstalled
    /// No install of the hook into this file is on record.
    case notInstalled
    /// The file lies outside the folder this build may change, as every real
    /// profile does for the Dev build.
    case outsideAllowedFolder
    /// The file changed after it was read, so nothing was written. Look again.
    case changedMeanwhile
    /// The hook tool's path is not absolute, or holds a character a shell
    /// command cannot carry safely.
    case unsafeToolPath
    /// The hook tool is missing from this copy of the app.
    case toolMissing
    /// A file could not be written. The settings file is unchanged.
    case writeFailed

    /// Whether the user is shown the lines to change by hand.
    public var offersManualLines: Bool {
        switch self {
        case .missing, .notAFile, .unreadable, .tooLarge, .notJSONObject, .unusualFormatting,
             .hooksNotObjectOfLists, .hardLinked, .writeFailed: true
        case .alreadyInstalled, .notInstalled, .outsideAllowedFolder, .changedMeanwhile, .unsafeToolPath,
             .toolMissing: false
        }
    }
}

/// The shell command a settings file runs for the hook: the tool's absolute
/// path in single quotes, with `--target dev` for the Dev build.
public struct HookCommand: Equatable, Sendable {
    /// The command as written into the settings file.
    public let text: String
    /// The tool's absolute path.
    public let toolPath: String
    /// The tool's file name, which marks a hook of this app in any settings file.
    public let toolName: String

    /// The command that runs the tool at `toolPath` for `target`.
    ///
    /// Release names no target, so the hook reaches the daily copy. Throws
    /// ``HookInstallError/unsafeToolPath`` when `toolPath` is not absolute,
    /// has no file name, or holds a control character such as a newline.
    public init(toolPath: String, target: HookTarget) throws {
        let name = (toolPath as NSString).lastPathComponent
        guard toolPath.hasPrefix("/"), !name.isEmpty, name != "/",
              !toolPath.unicodeScalars.contains(where: { $0.value < 0x20 || $0.value == 0x7F })
        else { throw HookInstallError.unsafeToolPath }
        // Inside single quotes only a single quote is special. It closes the
        // quotes, adds an escaped quote, and opens them again.
        let quoted = "'" + toolPath.replacing("'", with: #"'\''"#) + "'"
        text = target == .dev ? quoted + " --target dev" : quoted
        self.toolPath = toolPath
        toolName = name
    }
}

/// A settings file's text with the hook added, and what the install created.
public struct HookSettingsEdit: Equatable, Sendable {
    /// The new text of the file.
    public let data: Data
    /// Whether the install added the `hooks` key.
    public let createdHooks: Bool
    /// The events whose list the install added, in the order it added them.
    public let createdEvents: [String]
    /// Whether the file had no bytes at all before the install.
    public let wasEmpty: Bool
}

/// What the installer does to the text of a Claude Code settings file.
///
/// Pure: it takes the file's bytes and returns new ones, and reads nothing
/// from the disk.
public enum HookSettings {
    /// The largest settings file the installer reads, in bytes.
    public static let maximumSize = 4 * 1024 * 1024

    /// The group added to each event's list: one hook that runs `command`.
    public static func group(command: String) -> JSONValue {
        .object([JSONMember("hooks", .array([.object([
            JSONMember("type", .string("command")),
            JSONMember("command", .string(command)),
            // The tool takes milliseconds. This only bounds a hang.
            JSONMember("timeout", .number("5")),
        ])]))])
    }

    /// The lines to add by hand, or to take out again: a whole settings file
    /// that holds only the hook, two-space.
    public static func manualLines(command: String) -> String {
        JSONValue.object([JSONMember("hooks", .object(HookEvent.handledNames.map {
            JSONMember($0, .array([group(command: command)]))
        }))]).formatted
    }

    /// `data` with one group running `command` added at the end of the list
    /// of each event in ``HookEvent/handledNames``, and what that created.
    ///
    /// A list or `hooks` that is missing is added at the end of its object.
    /// The file keeps whether it ends with a newline. A file of zero bytes
    /// counts as an empty object. Throws ``HookInstallError/alreadyInstalled``
    /// when any hook's command holds `marker`, the tool's name, and the
    /// errors of ``checked(_:)``.
    public static func installing(command: String, marker: String, into data: Data) throws -> HookSettingsEdit {
        var text = try SettingsText(data)
        guard !commands(in: text.members).contains(where: { $0.contains(marker) }) else {
            throw HookInstallError.alreadyInstalled
        }
        var hooks = text.members["hooks"]?.members ?? []
        var createdEvents: [String] = []
        for event in HookEvent.handledNames {
            if hooks[event] == nil {
                createdEvents.append(event)
            }
            hooks[event] = .array((hooks[event]?.values ?? []) + [group(command: command)])
        }
        let createdHooks = text.members["hooks"] == nil
        text.members["hooks"] = .object(hooks)
        return HookSettingsEdit(
            data: text.data, createdHooks: createdHooks, createdEvents: createdEvents, wasEmpty: text.isEmptyFile,
        )
    }

    /// `data` without the groups the install of `command` added, and without
    /// the containers that install created once they are empty.
    ///
    /// A group is removed only from the list of an event in
    /// ``HookEvent/handledNames``, the lists the install writes to, and only
    /// when every hook in it runs exactly `command`.
    /// An event list is removed only when it is in `createdEvents` and is
    /// empty, and `hooks` only when `createdHooks` and it is empty. When
    /// `wasEmpty` and nothing else is left, the result has zero bytes. Every
    /// other key, list and group is kept as it is. When no group runs
    /// `command`, `data` comes back unchanged. Throws the errors of ``checked(_:)``.
    public static func uninstalling(
        command: String,
        createdHooks: Bool,
        createdEvents: [String],
        wasEmpty: Bool,
        from data: Data,
    ) throws -> Data {
        var text = try SettingsText(data)
        guard var hooks = text.members["hooks"]?.members else { return data }
        var removed = 0
        // Only the lists the install writes to. ponytail: an event dropped
        // from the list later keeps an older install's group there.
        let events = Set(HookEvent.handledNames.map { Array($0.utf8) })
        for index in hooks.indices where events.contains(Array(hooks[index].key.utf8)) {
            if let groups = hooks[index].value.values {
                let kept = groups.filter { !isOwn($0, command: command) }
                removed += groups.count - kept.count
                hooks[index].value = .array(kept)
            }
        }
        // Rule 7: a file that holds none of the install's own groups is left alone.
        guard removed > 0 else { return data }
        for event in createdEvents where hooks[event] == .array([]) {
            hooks[event] = nil
        }
        text.members["hooks"] = createdHooks && hooks.isEmpty ? nil : .object(hooks)
        text.isEmptyFile = wasEmpty
        return text.data
    }

    /// Checks that the installer may edit `data`, and returns it unchanged.
    ///
    /// Throws ``HookInstallError/tooLarge`` above ``maximumSize``,
    /// ``HookInstallError/notJSONObject``, ``HookInstallError/unusualFormatting``
    /// when two-space JSON would not give back the same bytes, and
    /// ``HookInstallError/hooksNotObjectOfLists``. Zero bytes pass.
    @discardableResult
    public static func checked(_ data: Data) throws -> Data {
        try SettingsText(data).data
    }

    /// Every hook command in the settings `data`, in any formatting, or none
    /// when `data` is not a JSON object.
    public static func commands(in data: Data) -> [String] {
        // Text that cannot be read holds no command to find.
        guard !data.isEmpty, let members = (try? JSONValue(parsing: data))?.members else { return [] }
        return commands(in: members)
    }

    /// The top-level keys whose value differs between the settings `data`
    /// and `backup`, in the order of `data` and then of `backup`, or `nil`
    /// when either is not a JSON object. Zero bytes count as an empty object.
    public static func differingKeys(_ data: Data, from backup: Data) -> [String]? {
        /// Text that cannot be read has no keys to compare.
        func members(_ data: Data) -> [JSONMember]? {
            data.isEmpty ? [] : (try? JSONValue(parsing: data))?.members
        }
        guard let now = members(data), let before = members(backup) else { return nil }
        let keys = now.map(\.key) + before.map(\.key).filter { key in
            !now.contains { $0.key.utf8.elementsEqual(key.utf8) }
        }
        return keys.filter { now[$0] != before[$0] }
    }

    private static func commands(in members: [JSONMember]) -> [String] {
        (members["hooks"]?.members ?? []).flatMap { event in
            (event.value.values ?? []).flatMap { group in
                (group.members?["hooks"]?.values ?? []).compactMap { hook in
                    if case let .string(command)? = hook.members?["command"] {
                        command
                    } else {
                        nil
                    }
                }
            }
        }
    }

    private static func isOwn(_ group: JSONValue, command: String) -> Bool {
        guard let hooks = group.members?["hooks"]?.values, !hooks.isEmpty else { return false }
        return hooks.allSatisfy { $0.members?["command"] == .string(command) }
    }
}

/// A settings file the installer may edit: a JSON object that two-space JSON
/// writes back byte for byte, or zero bytes.
private struct SettingsText {
    var members: [JSONMember] = []
    var endsWithNewline = false
    /// Whether the file has zero bytes. An empty object is then written as zero bytes.
    var isEmptyFile = true

    init(_ data: Data) throws {
        guard !data.isEmpty else { return }
        guard data.count <= HookSettings.maximumSize else { throw HookInstallError.tooLarge }
        // Every way the text fails to parse is the same refusal.
        guard let members = (try? JSONValue(parsing: data))?.members else { throw HookInstallError.notJSONObject }
        self.members = members
        endsWithNewline = data.last == UInt8(ascii: "\n")
        isEmptyFile = false
        guard self.data == data else { throw HookInstallError.unusualFormatting }
        if let hooks = members["hooks"] {
            let isObjectOfLists = hooks.members?.allSatisfy { event in
                event.value.values?.allSatisfy { $0.members != nil } == true
            }
            guard isObjectOfLists == true else { throw HookInstallError.hooksNotObjectOfLists }
        }
    }

    var data: Data {
        if isEmptyFile, members.isEmpty {
            return Data()
        }
        return Data((JSONValue.object(members).formatted + (endsWithNewline ? "\n" : "")).utf8)
    }
}
