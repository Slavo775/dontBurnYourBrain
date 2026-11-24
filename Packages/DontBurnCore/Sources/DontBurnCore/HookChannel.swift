import Foundation

/// Which build the hook tool reports to.
///
/// Hooks in real profiles name no target and reach the Release build. A
/// scratch project names `--target dev`, or sets `DONTBURN_TARGET=dev`, to
/// reach the Dev build. See "Release and Dev" in `docs/spikes/claude-hook.md`.
public enum HookTarget: String, Sendable {
    /// The daily copy.
    case release
    /// The development build.
    case dev

    /// The target `arguments` and `environment` name, or `nil` when they name
    /// one that does not exist.
    ///
    /// `--target <name>` among `arguments` wins over `DONTBURN_TARGET`. When
    /// neither names one, or the variable is empty, the target is ``release``.
    /// An unknown name, or `--target` without one, gives `nil`, so a typo
    /// sends nothing rather than reaching the other build.
    public init?(arguments: [String], environment: [String: String]) {
        let name: String? = if let flag = arguments.firstIndex(of: "--target") {
            arguments.indices.contains(flag + 1) ? arguments[flag + 1] : nil
        } else if let variable = environment["DONTBURN_TARGET"], !variable.isEmpty {
            variable
        } else {
            Self.release.rawValue
        }
        guard let target = name.flatMap(Self.init(rawValue:)) else { return nil }
        self = target
    }

    /// The bundle identifier of the target's build in `info`, the hook tool's
    /// own info dictionary, or `nil` when it holds none.
    ///
    /// `project.yml` writes both identifiers into the tool's Info.plist, as
    /// `DontBurnReleaseBundleIdentifier` and `DontBurnDevBundleIdentifier`,
    /// from the same settings the app takes its own from.
    public func bundleIdentifier(in info: [String: Any]) -> String? {
        let key = switch self {
        case .release: "DontBurnReleaseBundleIdentifier"
        case .dev: "DontBurnDevBundleIdentifier"
        }
        return (info[key] as? String).flatMap { $0.isEmpty ? nil : $0 }
    }
}

/// Where the hook tool sends events to the app: a Unix datagram socket in the
/// folder named after the app's bundle identifier, so each build has its own.
public enum HookChannel {
    /// The socket's file name, next to the stores.
    public static let fileName = "Hook.socket"

    /// The socket of the build with `bundleIdentifier`, in its folder inside `applicationSupport`.
    ///
    /// Only builds the URL. Nothing is read or created on disk.
    public static func url(bundleIdentifier: String, applicationSupport: URL) -> URL {
        StoreLocation.directory(bundleIdentifier: bundleIdentifier, applicationSupport: applicationSupport)
            .appending(path: fileName, directoryHint: .notDirectory)
    }
}

/// Why a Unix socket address cannot be made.
public enum UnixSocketAddressError: Error, Equatable, Sendable {
    /// The path does not fit a socket address, which holds 103 bytes and a closing zero.
    case pathTooLong
    /// The path is empty or holds a zero byte.
    case invalidPath
}

/// The address of a Unix socket at a path, checked to fit.
public struct UnixSocketAddress: Sendable {
    private var address = sockaddr_un()

    /// The address of the socket at `path`.
    ///
    /// Throws ``UnixSocketAddressError/pathTooLong`` when `path` takes more
    /// than 103 bytes in UTF-8, and ``UnixSocketAddressError/invalidPath``
    /// when it is empty or holds a zero byte.
    public init(path: String) throws {
        let bytes = Array(path.utf8)
        guard !bytes.isEmpty, !bytes.contains(0) else { throw UnixSocketAddressError.invalidPath }
        try withUnsafeMutableBytes(of: &address.sun_path) { field in
            // One byte stays zero to end the path.
            guard bytes.count < field.count else { throw UnixSocketAddressError.pathTooLong }
            field.copyBytes(from: bytes)
        }
        address.sun_family = sa_family_t(AF_UNIX)
        address.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
    }

    /// Calls `body` with the address as the socket calls take it, and its length.
    public func withSocketAddress<Result>(
        _ body: (UnsafePointer<sockaddr>, socklen_t) throws -> Result,
    ) rethrows -> Result {
        try withUnsafePointer(to: address) { pointer in
            try pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                try body($0, socklen_t(MemoryLayout<sockaddr_un>.size))
            }
        }
    }
}
