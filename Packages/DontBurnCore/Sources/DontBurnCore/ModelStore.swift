import Foundation
import SwiftData

/// How the store moves from one schema version to the next.
///
/// There is one version so far. A later version adds its schema and a stage here.
public enum DontBurnMigrationPlan: SchemaMigrationPlan {
    /// Every schema version, oldest first.
    public static var schemas: [any VersionedSchema.Type] {
        [SchemaV1.self]
    }

    /// The steps between versions.
    public static var stages: [MigrationStage] {
        []
    }
}

/// How the local store, the one this Mac keeps for itself, moves from one
/// schema version to the next.
public enum LocalMigrationPlan: SchemaMigrationPlan {
    /// Every local schema version, oldest first.
    public static var schemas: [any VersionedSchema.Type] {
        [LocalSchemaV1.self]
    }

    /// The steps between versions.
    public static var stages: [MigrationStage] {
        []
    }
}

/// The one place that builds the model containers: the synced store and the
/// local store.
///
/// Sync is off until phase 6, so every configuration sets `cloudKitDatabase`
/// to `.none` on purpose. The local store keeps `.none` for good: what it holds,
/// such as folder paths, belongs to this Mac and is never synced.
public enum ModelStore {
    /// The store file's name inside the store's folder.
    public static let fileName = "DontBurn.store"

    /// The local store file's name, next to ``fileName`` in the same folder.
    public static let localFileName = "Local.store"

    /// The current schema.
    public static var schema: Schema {
        Schema(versionedSchema: SchemaV1.self)
    }

    /// The current local schema.
    public static var localSchema: Schema {
        Schema(versionedSchema: LocalSchemaV1.self)
    }

    /// A container kept only in memory, for tests, previews and the sample data.
    public static func inMemory() throws -> ModelContainer {
        try container(ModelConfiguration(schema: schema, isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    /// A container whose store is ``fileName`` inside `directory`.
    ///
    /// Creates `directory` when it is missing. Pass the folder from
    /// ``StoreLocation/directory(bundleIdentifier:applicationSupport:)``, never
    /// SwiftData's default location.
    public static func onDisk(in directory: URL) throws -> ModelContainer {
        let url = try storeURL(fileName, in: directory)
        return try container(ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    }

    /// A local container kept only in memory, for tests, previews and the sample data.
    public static func localInMemory() throws -> ModelContainer {
        // Never synced, so `.none` stays here when sync arrives.
        try localContainer(ModelConfiguration(
            "Local", schema: localSchema, isStoredInMemoryOnly: true, cloudKitDatabase: .none,
        ))
    }

    /// A local container whose store is ``localFileName`` inside `directory`,
    /// the same folder ``onDisk(in:)`` gets.
    ///
    /// Creates `directory` when it is missing.
    public static func localOnDisk(in directory: URL) throws -> ModelContainer {
        let url = try storeURL(localFileName, in: directory)
        // Never synced, so `.none` stays here when sync arrives.
        return try localContainer(ModelConfiguration("Local", schema: localSchema, url: url, cloudKitDatabase: .none))
    }

    private static func storeURL(_ name: String, in directory: URL) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory.appending(path: name, directoryHint: .notDirectory)
    }

    private static func container(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: DontBurnMigrationPlan.self, configurations: configuration)
    }

    private static func localContainer(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: localSchema, migrationPlan: LocalMigrationPlan.self, configurations: configuration)
    }
}
