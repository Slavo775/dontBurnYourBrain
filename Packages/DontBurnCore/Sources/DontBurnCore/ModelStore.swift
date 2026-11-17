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

/// The one place that builds the model container.
///
/// Sync is off until phase 6, so every configuration sets `cloudKitDatabase`
/// to `.none` on purpose.
public enum ModelStore {
    /// The store file's name inside the store's folder.
    public static let fileName = "DontBurn.store"

    /// The current schema.
    public static var schema: Schema {
        Schema(versionedSchema: SchemaV1.self)
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
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: fileName, directoryHint: .notDirectory)
        return try container(ModelConfiguration(schema: schema, url: url, cloudKitDatabase: .none))
    }

    private static func container(_ configuration: ModelConfiguration) throws -> ModelContainer {
        try ModelContainer(for: schema, migrationPlan: DontBurnMigrationPlan.self, configurations: configuration)
    }
}
