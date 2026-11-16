@testable import DontBurnCore
import Foundation
import Testing

@Test func `store folder is named after the bundle identifier`() {
    let support = URL(filePath: "/tmp/Application Support", directoryHint: .isDirectory)

    let release = StoreLocation.directory(bundleIdentifier: "com.example.app", applicationSupport: support)
    let dev = StoreLocation.directory(bundleIdentifier: "com.example.app.dev", applicationSupport: support)

    #expect(release.path() == "/tmp/Application%20Support/com.example.app/")
    #expect(dev != release)
}
