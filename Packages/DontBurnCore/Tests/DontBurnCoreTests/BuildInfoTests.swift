import DontBurnCore
import Foundation
import Testing

@Test func `a Dev bundle gives its version, build, variant and commit`() {
    let info = BuildInfo(infoDictionary: [
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "1",
        "DontBurnVariant": "Dev",
        "DontBurnCommit": "1a2b3c4",
    ])

    #expect(info.version == "0.1.0")
    #expect(info.build == "1")
    #expect(info.variant == .dev)
    #expect(info.commit == "1a2b3c4")
}

@Test func `a Release bundle is Release and carries no commit`() {
    let info = BuildInfo(infoDictionary: [
        "CFBundleShortVersionString": "0.1.0",
        "CFBundleVersion": "42",
        "DontBurnVariant": "Release",
    ])

    #expect(info.variant == .release)
    #expect(info.commit == nil)
}

@Test(arguments: [nil, "Beta", "dev", "DEV", "", 1] as [(any Sendable)?])
func `a missing, unknown or malformed variant counts as Release`(value: (any Sendable)?) {
    var dictionary: [String: Any] = ["DontBurnCommit": "1a2b3c4"]
    dictionary["DontBurnVariant"] = value

    #expect(BuildInfo(infoDictionary: dictionary).variant == .release)
}

@Test(arguments: [nil, "", 7] as [(any Sendable)?])
func `a missing, empty or non-string commit is nil`(value: (any Sendable)?) {
    var dictionary: [String: Any] = ["DontBurnVariant": "Dev"]
    dictionary["DontBurnCommit"] = value

    #expect(BuildInfo(infoDictionary: dictionary).commit == nil)
}

@Test func `a version or build that is not a string counts as empty`() {
    let info = BuildInfo(infoDictionary: ["CFBundleShortVersionString": 1, "CFBundleVersion": 2])

    #expect(info.version.isEmpty)
    #expect(info.build.isEmpty)
}

@Test func `an empty dictionary is an empty Release build without a commit`() {
    let info = BuildInfo(infoDictionary: [:])

    #expect(info.version.isEmpty)
    #expect(info.build.isEmpty)
    #expect(info.variant == .release)
    #expect(info.commit == nil)
}

@Test func `two builds with the same values are equal, and differ by any one of them`() {
    let dev: [String: Any] = [
        "CFBundleShortVersionString": "0.1.0", "CFBundleVersion": "1",
        "DontBurnVariant": "Dev", "DontBurnCommit": "1a2b3c4",
    ]

    #expect(BuildInfo(infoDictionary: dev) == BuildInfo(infoDictionary: dev))
    for key in dev.keys {
        var changed = dev
        changed[key] = nil
        #expect(BuildInfo(infoDictionary: changed) != BuildInfo(infoDictionary: dev), "without \(key)")
    }
}

/// The build phase writes `APP_VARIANT` into the bundle, so each raw value must
/// be one of the values `project.yml` sets.
@Test func `the variant raw values match APP_VARIANT in project.yml`() throws {
    let root = URL(filePath: #filePath)
        .deletingLastPathComponent() // DontBurnCoreTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // DontBurnCore
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent()
    let project = try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
    let values = Set(project.split(separator: "\n").compactMap { line -> String? in
        let parts = line.split(separator: ":", maxSplits: 1)
        guard parts.count == 2, parts[0].trimmingCharacters(in: .whitespaces) == "APP_VARIANT" else { return nil }
        return parts[1].trimmingCharacters(in: .whitespaces)
    })

    #expect(BuildInfo.Variant.dev.rawValue == "Dev")
    #expect(BuildInfo.Variant.release.rawValue == "Release")
    #expect(values == ["Dev", "Release"])
}
