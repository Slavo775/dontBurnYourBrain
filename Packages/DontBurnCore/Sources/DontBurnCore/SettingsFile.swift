import Foundation

// The file system side of the hook installer: which settings files it may
// touch, how it reads one, and how it writes a file safely.

/// The folder settings files may be read and written in.
struct SettingsScope: Sendable {
    /// The folder as given, standardized, or `nil` for none.
    private let given: String?
    /// The folder with its symlinks resolved, or `nil` for none.
    private let real: String?

    /// The folder `folder`, or none when it is `nil` or not absolute.
    init(_ folder: String?) {
        let folder = folder?.hasPrefix("/") == true ? folder : nil
        given = folder.map(FolderPath.standardized)
        real = folder.map(FolderPath.resolved)
    }

    /// The real path of `path`, or `nil` when it lies outside the folder.
    ///
    /// `path` is resolved only when its own spelling lies inside the folder,
    /// so a path outside it is never looked at, and the real path must lie inside too.
    func resolve(_ path: String) -> String? {
        guard let given, let real, path.hasPrefix("/") else { return nil }
        let spelled = FolderPath.standardized(path)
        guard FolderPath.path(spelled, isInside: given) || FolderPath.path(spelled, isInside: real) else { return nil }
        let resolved = FolderPath.resolved(spelled)
        return FolderPath.path(resolved, isInside: real) ? resolved : nil
    }
}

/// A settings file as it was read: its bytes, inode, mode and links.
struct SettingsFile {
    let path: String
    let data: Data
    let inode: UInt64
    let mode: mode_t
    /// How many hard links the file has.
    let linkCount: Int

    /// A new file beside the settings file, not yet renamed over it.
    struct Staged {
        let path: String
        let inode: UInt64
    }

    init(path: String) throws {
        var info = stat()
        guard stat(path, &info) == 0 else {
            throw errno == ENOENT ? HookInstallError.missing : HookInstallError.unreadable
        }
        guard info.st_mode & S_IFMT == S_IFREG else { throw HookInstallError.notAFile }
        let data: Data
        do {
            let handle = try FileHandle(forReadingFrom: URL(filePath: path))
            defer { try? handle.close() } // Closing a file that was only read loses nothing.
            // One byte past the limit tells a file that is too large without reading all of it.
            data = try handle.read(upToCount: HookSettings.maximumSize + 1) ?? Data()
        } catch {
            throw HookInstallError.unreadable
        }
        guard data.count <= HookSettings.maximumSize else { throw HookInstallError.tooLarge }
        self.path = path
        self.data = data
        inode = UInt64(info.st_ino)
        mode = info.st_mode & 0o7777
        linkCount = Int(info.st_nlink)
    }

    /// The file at `path`, read to be written.
    ///
    /// Throws ``HookInstallError/hardLinked`` when the file has more than one
    /// hard link: the rename would leave the other name holding the old
    /// text, so a profile sharing it that way would quietly stop sharing it.
    static func writable(_ path: String) throws -> SettingsFile {
        let file = try SettingsFile(path: path)
        guard file.linkCount == 1 else { throw HookInstallError.hardLinked }
        return file
    }

    /// Writes `data` to a new file beside this one, with this one's mode, on the disk.
    func stage(_ data: Data) throws -> Staged {
        let folder = (path as NSString).deletingLastPathComponent
        let name = ".\((path as NSString).lastPathComponent).\(UUID().uuidString).tmp"
        let staged = (folder as NSString).appendingPathComponent(name)
        return try Staged(path: staged, inode: writeNewFile(data, at: staged, mode: mode))
    }

    /// Renames `staged` over this file, unless the file changed since it was read.
    ///
    /// ponytail: a write by another app between the last read and the rename
    /// is lost. The gap is a few microseconds, and Claude Code writes its
    /// settings rarely. A lock would need every writer to take it.
    func replace(with staged: Staged) throws {
        // A file that can no longer be read has changed too.
        guard (try? Self(path: path))?.data == data else { throw HookInstallError.changedMeanwhile }
        guard rename(staged.path, path) == 0 else { throw HookInstallError.writeFailed }
    }
}

/// Writes `data` to a new file at `path`, flushed to the disk, and returns its inode.
///
/// The file is made for this user alone, mode 0600, and gets `mode` only
/// once it holds all of `data`, so a file that may hold tokens is never
/// readable by others on the way. Never overwrites a file. Throws
/// ``HookInstallError/writeFailed``, and then leaves no file behind.
func writeNewFile(_ data: Data, at path: String, mode: mode_t) throws -> UInt64 {
    let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC, 0o600)
    guard descriptor >= 0 else { throw HookInstallError.writeFailed }
    var info = stat()
    let isWritten = data.withUnsafeBytes { bytes in
        var offset = 0
        while offset < bytes.count {
            let count = write(descriptor, bytes.baseAddress?.advanced(by: offset), bytes.count - offset)
            if count < 0, errno == EINTR {
                continue
            }
            guard count > 0 else { return false }
            offset += count
        }
        return true
    }
    // F_FULLFSYNC reaches the disk itself. A file system without it gets fsync.
    let isOnDisk = isWritten && fchmod(descriptor, mode) == 0
        && (fcntl(descriptor, F_FULLFSYNC) == 0 || fsync(descriptor) == 0)
        && fstat(descriptor, &info) == 0
    guard close(descriptor) == 0, isOnDisk else {
        unlink(path)
        throw HookInstallError.writeFailed
    }
    return UInt64(info.st_ino)
}
