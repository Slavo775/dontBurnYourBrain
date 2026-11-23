import Foundation
import SwiftData

/// Folder paths in the form the folder rule compares them.
///
/// Only ``resolved(_:)`` reads the disk. Everything else works on the text alone.
public enum FolderPath {
    /// The absolute `path` with every symlink resolved, so `/var/x` and
    /// `/private/var/x` give the same path.
    ///
    /// Uses `realpath(3)`, since Foundation's `resolvingSymlinksInPath` drops
    /// a leading `/private` and so gives the other spelling. When the folder
    /// does not exist, the deepest folder above it that does is resolved and
    /// the rest appended, so a folder not made yet still matches its parent's
    /// project. A `path` that is not absolute gives ``standardized(_:)``,
    /// never a path resolved against the app's working folder.
    public static func resolved(_ path: String) -> String {
        guard path.hasPrefix("/") else { return standardized(path) }
        if let real = realPath(path) {
            return real
        }
        var head = components(path)
        var tail: [Substring] = []
        while let last = head.popLast() {
            tail.insert(last, at: 0)
            if let real = realPath("/" + head.joined(separator: "/")) {
                return standardized(real + "/" + tail.joined(separator: "/"))
            }
        }
        return standardized(path)
    }

    private static func realPath(_ path: String) -> String? {
        guard let pointer = realpath(path, nil) else { return nil }
        defer { free(pointer) }
        return String(cString: pointer)
    }

    /// `path` as an absolute path without `.` and `..`, repeated slashes or
    /// a trailing slash. Symlinks stay as they are.
    public static func standardized(_ path: String) -> String {
        "/" + components(path).joined(separator: "/")
    }

    /// Whether `path` is `folder` itself or lies below it.
    ///
    /// Compares whole path components, never a string prefix, so
    /// `/code/acme` does not hold `/code/acme-web`. Symlinks are not resolved:
    /// pass resolved paths.
    public static func path(_ path: String, isInside folder: String) -> Bool {
        components(path).starts(with: components(folder))
    }

    /// The names along `path`, with `.` and `..` applied.
    static func components(_ path: String) -> [Substring] {
        var names: [Substring] = []
        for name in path.split(separator: "/") {
            switch name {
            case ".": continue
            case "..": _ = names.popLast()
            default: names.append(name)
            }
        }
        return names
    }
}

/// Why a folder cannot be given to a project.
public enum ProjectFolderError: Error, Equatable, Sendable {
    /// Another project, active or archived, in any workspace, holds the
    /// folder already. Carries that project's name.
    case taken(byProjectNamed: String)
}

/// The projects' folders on this Mac, and which project a folder belongs to.
///
/// The folders live in the local store, which never syncs, and name their
/// project by its identifier. A folder belongs to one project at most. A
/// folder whose project is gone is ignored.
public struct ProjectFolders {
    private let context: ModelContext

    /// Folders kept in `context`, a context of the local store.
    public init(context: ModelContext) {
        self.context = context
    }

    /// The project, among `projects`, whose folder holds `path`, or `nil`
    /// when no folder does.
    ///
    /// `path` is resolved first. See ``project(holdingResolved:folders:projects:)``.
    public func project(holding path: String, among projects: [Project]) throws -> Project? {
        try Self.project(
            holdingResolved: FolderPath.resolved(path),
            folders: context.fetch(FetchDescriptor<ProjectFolder>()),
            projects: projects,
        )
    }

    /// Gives the folder at `path` to `project`, with its symlinks resolved.
    ///
    /// `projects` is every project of every workspace, archived ones too.
    /// Throws ``ProjectFolderError/taken(byProjectNamed:)`` when another of
    /// them holds the folder. A folder the project holds already changes nothing.
    public func add(_ path: String, to project: Project, among projects: [Project]) throws {
        let resolved = FolderPath.resolved(path)
        let folders = try context.fetch(FetchDescriptor<ProjectFolder>())
        if let holder = Self.holder(ofResolved: resolved, folders: folders, projects: projects) {
            guard holder.id == project.id else { throw ProjectFolderError.taken(byProjectNamed: holder.name) }
            return
        }
        context.insert(ProjectFolder(projectID: project.id, path: resolved))
        try context.save()
    }

    /// Takes `folder` away from its project.
    public func remove(_ folder: ProjectFolder) throws {
        context.delete(folder)
        try context.save()
    }

    /// The project whose folder holds the resolved `path`, the one with the
    /// deepest folder when several do, or `nil` when none does.
    ///
    /// Only active projects of active workspaces count. Reads nothing from
    /// the disk: `path` and the folders' paths are compared as given.
    public static func project(
        holdingResolved path: String,
        folders: [ProjectFolder],
        projects: [Project],
    ) -> Project? {
        let active = byID(projects.filter { !$0.isArchived && $0.workspace?.isArchived == false })
        return folders
            .filter { active[$0.projectID] != nil && FolderPath.path(path, isInside: $0.path) }
            .max { FolderPath.components($0.path).count < FolderPath.components($1.path).count }
            .flatMap { active[$0.projectID] }
    }

    /// The project among `projects`, active or archived, whose folder is
    /// exactly the resolved `path`, or `nil` when none is.
    ///
    /// Reads nothing from the disk.
    public static func holder(ofResolved path: String, folders: [ProjectFolder], projects: [Project]) -> Project? {
        let all = byID(projects)
        let target = FolderPath.components(path)
        return folders
            .first { all[$0.projectID] != nil && FolderPath.components($0.path) == target }
            .flatMap { all[$0.projectID] }
    }

    private static func byID(_ projects: [Project]) -> [UUID: Project] {
        Dictionary(projects.map { ($0.id, $0) }) { first, _ in first }
    }
}
