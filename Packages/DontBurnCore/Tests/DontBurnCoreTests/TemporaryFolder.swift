import Foundation
import Testing

/// A folder made for one test in this user's temporary folder, and removed
/// when the test lets go of it.
///
/// Made below the folder macOS hands every process of this user, which is
/// spelled with `/var` while its real path starts with `/private/var`. That
/// folder is asked for directly, so a changed `TMPDIR` changes nothing.
final class TemporaryFolder {
    /// The name every test folder starts with, so cleanup removes nothing else.
    private static let prefix = "DontBurnCoreTests-"

    /// The user's temporary folder, spelled as macOS hands it out, without a trailing slash.
    let base: String
    /// The test's own folder, directly below ``base``.
    let path: String

    init() throws {
        base = try #require(Self.userTemporaryDirectory())
        path = (base as NSString).appendingPathComponent("\(Self.prefix)\(UUID().uuidString)")
        try FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: false)
    }

    /// The test folder as a file URL.
    var url: URL {
        URL(filePath: path, directoryHint: .isDirectory)
    }

    /// The path of `relative` below the test folder, made with its parents.
    @discardableResult
    func make(_ relative: String) throws -> String {
        let made = path(relative)
        try FileManager.default.createDirectory(atPath: made, withIntermediateDirectories: true)
        return made
    }

    /// The path of `relative` below the test folder, not made.
    func path(_ relative: String) -> String {
        (path as NSString).appendingPathComponent(relative)
    }

    deinit {
        // Looked at first: only this test's own folder, directly in the
        // user's temporary folder, is ever removed.
        let folder = path as NSString
        guard folder.lastPathComponent.hasPrefix(Self.prefix), folder.deletingLastPathComponent == base else { return }
        try? FileManager.default.removeItem(atPath: path) // Cleanup only.
    }

    /// `/var/folders/…/T`, from `confstr`, or `nil` when macOS has none.
    private static func userTemporaryDirectory() -> String? {
        let length = confstr(_CS_DARWIN_USER_TEMP_DIR, nil, 0)
        guard length > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: length)
        let written = confstr(_CS_DARWIN_USER_TEMP_DIR, &buffer, length)
        let bytes = buffer.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }
        guard written == length, let text = String(bytes: bytes, encoding: .utf8) else { return nil }
        return text.count > 1 && text.hasSuffix("/") ? String(text.dropLast()) : text
    }
}
