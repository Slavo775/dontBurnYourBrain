import Foundation

/// A Claude Code profile folder on this Mac, such as `~/.claude-acme`.
///
/// Of everything inside the folder, the app only ever reads `settings.json`.
public struct ClaudeProfile: Identifiable, Equatable, Sendable {
    /// The name of a profile's settings file, the only file the app reads in it.
    public static let settingsFileName = "settings.json"

    /// The folder's path as it was found or added.
    public let folder: String
    /// The real path of the folder's settings file, with every symlink
    /// resolved, or `nil` when it lies outside the folder this build may read.
    public let settingsFile: String?

    /// The profile in `folder`, whose settings resolve to `settingsFile`.
    public init(folder: String, settingsFile: String?) {
        self.folder = folder
        self.settingsFile = settingsFile
    }

    /// The folder's path.
    public var id: String {
        folder
    }

    /// The folder's own name, such as `.claude-acme`.
    public var name: String {
        (folder as NSString).lastPathComponent
    }

    /// The profiles at the top of `home` and the folders in `added`, the
    /// found ones by name, then the added ones in their order.
    ///
    /// In `home`, only the names are read, and `.claude` and every
    /// `.claude-*` that is a folder count. `home` is `nil` when none is
    /// looked at. A folder in `added` that is not absolute, or was found
    /// already, is left out. Each settings file is resolved only when it lies
    /// inside `allowedFolder`, as ``HookInstaller`` takes it, and is never read here.
    public static func find(inHome home: String?, added: [String], allowedFolder: String?) -> [ClaudeProfile] {
        var folders = home.map(profileFolders(in:)) ?? []
        for folder in added where folder.hasPrefix("/") {
            let folder = FolderPath.standardized(folder)
            if !folders.contains(folder) {
                folders.append(folder)
            }
        }
        let scope = SettingsScope(allowedFolder)
        return folders.map {
            ClaudeProfile(
                folder: $0,
                settingsFile: scope.resolve(($0 as NSString).appendingPathComponent(settingsFileName)),
            )
        }
    }

    /// The other profiles among `profiles` whose settings resolve to this one's file.
    public func sharers(among profiles: [ClaudeProfile]) -> [ClaudeProfile] {
        guard let settingsFile else { return [] }
        return profiles.filter { $0.id != id && $0.settingsFile == settingsFile }
    }

    private static func profileFolders(in home: String) -> [String] {
        let home = FolderPath.standardized(home)
        // A home folder that cannot be listed holds no profile to show.
        let names = (try? FileManager.default.contentsOfDirectory(atPath: home)) ?? []
        return names
            .filter { $0 == ".claude" || $0.hasPrefix(".claude-") }
            .sorted()
            .map { (home as NSString).appendingPathComponent($0) }
            .filter {
                var isFolder: ObjCBool = false
                return FileManager.default.fileExists(atPath: $0, isDirectory: &isFolder) && isFolder.boolValue
            }
    }
}
