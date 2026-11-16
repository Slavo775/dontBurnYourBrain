import Foundation

/// Where the app keeps its data.
///
/// An app that is not sandboxed shares `Application Support` with every other
/// such app, and SwiftData's default store lands directly in it. The store
/// therefore always gets an explicit folder named after the bundle identifier,
/// which also keeps the development build apart from the daily copy.
public enum StoreLocation {
    public static func directory(bundleIdentifier: String, applicationSupport: URL) -> URL {
        applicationSupport.appending(path: bundleIdentifier, directoryHint: .isDirectory)
    }
}
