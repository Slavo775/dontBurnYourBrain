import DontBurnCore
import Foundation
import Testing

/// The tool's info dictionary as the build writes it, with neutral identifiers.
private var info: [String: Any] {
    [
        "DontBurnReleaseBundleIdentifier": "com.example.dontburn",
        "DontBurnDevBundleIdentifier": "com.example.dontburn.dev",
    ]
}

private let support = URL(filePath: "/tmp/Application Support", directoryHint: .isDirectory)

/// The repository's root, four folders above this file.
private let root = URL(filePath: #filePath)
    .deletingLastPathComponent() // DontBurnCoreTests
    .deletingLastPathComponent() // Tests
    .deletingLastPathComponent() // DontBurnCore
    .deletingLastPathComponent() // Packages
    .deletingLastPathComponent()

// MARK: - Which build the tool reports to

@Test(arguments: [
    ([], [:]),
    ([], ["DONTBURN_TARGET": ""]),
    ([], ["DONTBURN_TARGET": "release"]),
    (["--target", "release"], [:]),
    (["--target", "release"], ["DONTBURN_TARGET": "dev"]),
] as [([String], [String: String])])
func `the target is release when nothing names dev, and --target wins over DONTBURN_TARGET`(
    arguments: [String],
    environment: [String: String],
) {
    #expect(HookTarget(arguments: arguments, environment: environment) == .release)
}

@Test(arguments: [
    ([], ["DONTBURN_TARGET": "dev"]),
    (["--target", "dev"], [:]),
    (["--target", "dev"], ["DONTBURN_TARGET": "release"]),
    (["--target", "dev"], ["DONTBURN_TARGET": "devv"]),
] as [([String], [String: String])])
func `the target is dev when --target or DONTBURN_TARGET names it, and --target wins`(
    arguments: [String],
    environment: [String: String],
) {
    #expect(HookTarget(arguments: arguments, environment: environment) == .dev)
}

@Test(arguments: [
    (["--target"], [:]),
    (["--target"], ["DONTBURN_TARGET": "dev"]),
    (["--target", ""], [:]),
    (["--target", "devv"], [:]),
    (["--target", "Dev"], [:]),
    (["--target", "--version"], [:]),
    ([], ["DONTBURN_TARGET": "devv"]),
    ([], ["DONTBURN_TARGET": "DEV"]),
    ([], ["DONTBURN_TARGET": " dev"]),
    (["--target=dev"], [:]),
    (["--target=release"], [:]),
    (["--target=devv"], [:]),
    (["--target="], [:]),
    (["--target=dev"], ["DONTBURN_TARGET": "dev"]),
    (["-t", "dev"], [:]),
    (["--targetdev"], [:]),
    (["--target-dev"], [:]),
    (["--Target", "dev"], [:]),
    (["dev"], [:]),
    (["dev"], ["DONTBURN_TARGET": "dev"]),
    (["--other", "dev"], [:]),
    (["--other", "--target", "dev"], [:]),
    (["--target", "dev", "extra"], [:]),
    (["--target", "dev", "--target", "dev"], [:]),
    (["--target", "release", "--target", "dev"], [:]),
] as [([String], [String: String])])
func `anything but no arguments or exactly --target and a known name gives no target, so nothing is sent`(
    arguments: [String],
    environment: [String: String],
) {
    #expect(HookTarget(arguments: arguments, environment: environment) == nil)
}

@Test func `each target reads its own bundle identifier, and never falls back to the other build's`() {
    #expect(HookTarget.release.bundleIdentifier(in: info) == "com.example.dontburn")
    #expect(HookTarget.dev.bundleIdentifier(in: info) == "com.example.dontburn.dev")

    let releaseOnly = info.filter { $0.key == "DontBurnReleaseBundleIdentifier" }
    let devOnly = info.filter { $0.key == "DontBurnDevBundleIdentifier" }
    #expect(HookTarget.dev.bundleIdentifier(in: releaseOnly) == nil)
    #expect(HookTarget.release.bundleIdentifier(in: devOnly) == nil)
}

@Test(arguments: [nil, "", 7] as [(any Sendable)?])
func `a missing, empty or non-string bundle identifier is none`(value: (any Sendable)?) {
    var dictionary: [String: Any] = [:]
    dictionary["DontBurnReleaseBundleIdentifier"] = value
    dictionary["DontBurnDevBundleIdentifier"] = value

    #expect(HookTarget.release.bundleIdentifier(in: dictionary) == nil)
    #expect(HookTarget.dev.bundleIdentifier(in: dictionary) == nil)
}

// MARK: - Each build's channel

@Test func `the Dev and Release builds get different channels, each in its own bundle folder`() {
    let release = HookChannel.url(bundleIdentifier: "com.example.dontburn", applicationSupport: support)
    let dev = HookChannel.url(bundleIdentifier: "com.example.dontburn.dev", applicationSupport: support)

    #expect(release.path(percentEncoded: false) == "/tmp/Application Support/com.example.dontburn/Hook.socket")
    #expect(dev.path(percentEncoded: false) == "/tmp/Application Support/com.example.dontburn.dev/Hook.socket")
    #expect(release != dev)
    #expect(dev.deletingLastPathComponent() == StoreLocation.directory(
        bundleIdentifier: "com.example.dontburn.dev", applicationSupport: support,
    ))
}

@Test func `the tool's Info.plist maps each target to its own build's identifier from project.yml`() throws {
    let plist = try Data(contentsOf: root.appending(path: "Tools/dontburn-hook/Info.plist"))
    let toolInfo = try #require(PropertyListSerialization.propertyList(from: plist, format: nil) as? [String: Any])

    #expect(HookTarget.release.bundleIdentifier(in: toolInfo) == "$(DONTBURN_RELEASE_BUNDLE_IDENTIFIER)")
    #expect(HookTarget.dev.bundleIdentifier(in: toolInfo) == "$(DONTBURN_DEV_BUNDLE_IDENTIFIER)")

    // The app's Debug build takes the Dev identifier, its Release build the Release one.
    let project = try String(contentsOf: root.appending(path: "project.yml"), encoding: .utf8)
    let lines = project.split(separator: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
    var identifiers: [String: String] = [:]
    for (index, line) in lines.enumerated() where line == "Debug:" || line == "Release:" {
        identifiers[String(line.dropLast())] = lines[(index + 1)...]
            .first { $0.hasPrefix("PRODUCT_BUNDLE_IDENTIFIER:") }?
            .dropFirst("PRODUCT_BUNDLE_IDENTIFIER:".count).trimmingCharacters(in: .whitespaces)
    }
    #expect(identifiers == [
        "Debug": "$(DONTBURN_DEV_BUNDLE_IDENTIFIER)", "Release": "$(DONTBURN_RELEASE_BUNDLE_IDENTIFIER)",
    ])
    #expect(lines.contains("DONTBURN_DEV_BUNDLE_IDENTIFIER: $(DONTBURN_RELEASE_BUNDLE_IDENTIFIER).dev"))
}

// MARK: - The socket's address

@Test func `a socket path of 103 bytes fits, and one of 104 does not`() throws {
    let fits = "/" + String(repeating: "a", count: 102)
    let tooLong = fits + "a"
    // Counted in bytes: each é takes two.
    let wideFits = "/" + String(repeating: "é", count: 51)
    let wideTooLong = wideFits + "a"

    #expect(throws: Never.self) { try UnixSocketAddress(path: fits) }
    #expect(throws: Never.self) { try UnixSocketAddress(path: wideFits) }
    #expect(throws: UnixSocketAddressError.pathTooLong) { try UnixSocketAddress(path: tooLong) }
    #expect(throws: UnixSocketAddressError.pathTooLong) { try UnixSocketAddress(path: wideTooLong) }
}

@Test(arguments: ["", "/tmp/Hook\0.socket", "\0"])
func `an empty path, or one with a zero byte, is no socket address`(path: String) {
    #expect(throws: UnixSocketAddressError.invalidPath) { try UnixSocketAddress(path: path) }
}

@Test func `the address holds the path, its family and its length`() throws {
    let path = "/tmp/Application Support/com.example.dontburn.dev/Hook.socket"
    let address = try UnixSocketAddress(path: path)

    address.withSocketAddress { pointer, length in
        #expect(Int(length) == MemoryLayout<sockaddr_un>.size)
        pointer.withMemoryRebound(to: sockaddr_un.self, capacity: 1) { unix in
            #expect(Int32(unix.pointee.sun_family) == AF_UNIX)
            #expect(Int(unix.pointee.sun_len) == MemoryLayout<sockaddr_un>.size)
            var field = unix.pointee.sun_path
            let stored = withUnsafeBytes(of: &field) { bytes in
                String(bytes: bytes.prefix { $0 != 0 }, encoding: .utf8)
            }
            #expect(stored == path)
        }
    }
}

@Test func `a datagram sent to an address of 103 bytes reaches the socket bound there`() throws {
    var template = Array("/tmp/dontburn-test.XXXXXX".utf8CString)
    let folder = try #require(mkdtemp(&template).map { String(cString: $0) })
    defer { rmdir(folder) }
    let path = folder + "/" + String(repeating: "s", count: 103 - folder.utf8.count - 1)
    #expect(path.utf8.count == 103)
    let address = try UnixSocketAddress(path: path)

    let receiver = socket(AF_UNIX, SOCK_DGRAM, 0)
    let sender = socket(AF_UNIX, SOCK_DGRAM, 0)
    defer {
        close(receiver)
        close(sender)
        unlink(path)
    }
    #expect(address.withSocketAddress { bind(receiver, $0, $1) } == 0)
    let message = Array("{\"hook_event_name\":\"Stop\"}".utf8)
    let sent = address.withSocketAddress { sendto(sender, message, message.count, MSG_DONTWAIT, $0, $1) }
    var buffer = [UInt8](repeating: 0, count: 64)
    let count = recv(receiver, &buffer, buffer.count, MSG_DONTWAIT)

    #expect(sent == message.count)
    #expect(Array(buffer.prefix(max(count, 0))) == message)
}
