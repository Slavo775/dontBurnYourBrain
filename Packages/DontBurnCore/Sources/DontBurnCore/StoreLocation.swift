import Foundation

/// Where the app keeps its data.
///
/// An app that is not sandboxed shares `Application Support` with every other
/// such app, and SwiftData's default store lands directly in it. The store
/// therefore always gets an explicit folder named after the bundle identifier,
/// which also keeps the development build apart from the daily copy.
public enum StoreLocation {
    /// The folder named `bundleIdentifier` inside `applicationSupport`, where the store lives.
    ///
    /// Only builds the URL. Nothing is read or created on disk.
    public static func directory(bundleIdentifier: String, applicationSupport: URL) -> URL {
        applicationSupport.appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }
}
