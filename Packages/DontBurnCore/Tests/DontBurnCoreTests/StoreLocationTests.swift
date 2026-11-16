import Foundation
import Testing

@testable import DontBurnCore

@Test func storeFolderIsNamedAfterTheBundleIdentifier() {
    let support = URL(filePath: "/tmp/Application Support", directoryHint: .isDirectory)

    let release = StoreLocation.directory(bundleIdentifier: "com.example.app", applicationSupport: support)
    let dev = StoreLocation.directory(bundleIdentifier: "com.example.app.dev", applicationSupport: support)

    #expect(release.path() == "/tmp/Application%20Support/com.example.app/")
    #expect(dev != release)
}
