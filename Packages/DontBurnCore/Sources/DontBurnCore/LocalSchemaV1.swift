import Foundation
import SwiftData

// What belongs to this Mac only, such as folder paths, lives in a store of its
// own that never syncs. Nothing links it to the synced store but identifiers,
// since SwiftData has no relationship across two stores. Model and property
// names are hard to change once a user has the store, so choose them with care.

/// The first version of the local data model, kept on this Mac and never synced.
public enum LocalSchemaV1: VersionedSchema {
    /// The version number of this schema.
    public static let versionIdentifier = Schema.Version(1, 0, 0)

    /// Every model of this version.
    public static var models: [any PersistentModel.Type] {
        [ProjectFolder.self]
    }

    /// A folder on this Mac that belongs to one project.
    @Model
    public final class ProjectFolder {
        /// The folder's own identifier.
        public var id = UUID()
        /// The ``SchemaV1/Project/id`` of the project the folder belongs to.
        public var projectID = UUID()
        /// The folder's absolute path, with symlinks resolved when it was added.
        public var path = ""

        /// The folder at `path`, given to the project with `projectID`.
        public init(projectID: UUID, path: String) {
            self.projectID = projectID
            self.path = path
        }
    }
}

/// A folder on this Mac that belongs to one project. See ``LocalSchemaV1/ProjectFolder``.
public typealias ProjectFolder = LocalSchemaV1.ProjectFolder
