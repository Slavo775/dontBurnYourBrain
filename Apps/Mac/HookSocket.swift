import Darwin
import DontBurnCore
import Foundation

/// The app's end of the hook channel: receives the hook tool's messages.
@MainActor
protocol HookMessageReceiving: AnyObject {
    /// Starts receiving, and hands each message to `receive` on the main
    /// actor, in the order they came, with the time each came.
    ///
    /// Throws when the channel cannot be opened.
    func start(receiving receive: @escaping @MainActor (Data, Date) -> Void) throws

    /// Stops receiving and removes the channel.
    func stop()
}

/// Why the hook socket could not be opened. Names no path, so it can go to the log.
enum HookSocketError: Error {
    /// Another running copy of this build listens on the socket.
    case inUse
    /// Something other than a socket sits at the socket's path.
    case notASocket
    /// The socket's folder could not be made.
    case folderUnavailable
    /// A system call failed with an `errno` code.
    case system(call: String, code: Int32)
}

/// The hook channel as a Unix datagram socket that only this user can send to.
///
/// One datagram is one message, so nothing is framed and no sender is waited
/// for: the hook tool sends without blocking and is gone. A message larger
/// than ``HookEvent/maximumSize`` arrives cut to one byte more, which
/// ``HookEvent/decode(_:)`` then refuses.
///
/// Sending to a socket needs write permission on its file, so mode 0600 keeps
/// other users of the Mac out. For the moment between `bind` and `chmod`,
/// `~/Library` itself is open to its owner only.
@MainActor
final class HookSocket: HookMessageReceiving {
    /// Room for a burst of events while the main actor is busy: hundreds of
    /// typical ones, or 16 of the largest.
    private static let receiveBufferSize = Int32(16 * HookEvent.maximumSize)

    private let path: String
    private var source: (any DispatchSourceRead)?

    /// The socket at `url`, which ``start(receiving:)`` opens.
    init(url: URL) {
        path = url.path(percentEncoded: false)
    }

    func start(receiving receive: @escaping @MainActor (Data, Date) -> Void) throws {
        guard source == nil else { return }
        let address = try UnixSocketAddress(path: path)
        do {
            let folder = URL(filePath: path).deletingLastPathComponent()
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            // The error's description holds the path.
            throw HookSocketError.folderUnavailable
        }
        try removeLeftover(at: address)
        let socket = try check("socket", Darwin.socket(AF_UNIX, SOCK_DGRAM, 0))
        do {
            try check("bind", address.withSocketAddress { bind(socket, $0, $1) })
        } catch {
            close(socket)
            throw error
        }
        do {
            try check("chmod", chmod(path, 0o600))
            var bufferSize = Self.receiveBufferSize
            let size = socklen_t(MemoryLayout<Int32>.size)
            try check("setsockopt", setsockopt(socket, SOL_SOCKET, SO_RCVBUF, &bufferSize, size))
            try check("fcntl", fcntl(socket, F_SETFL, O_NONBLOCK))
        } catch {
            close(socket)
            unlink(path)
            throw error
        }
        let source = Self.readSource(of: socket, receive: receive)
        source.resume()
        self.source = source
    }

    func stop() {
        guard let source else { return }
        source.cancel()
        self.source = nil
        // ponytail: removes whatever socket is at the path now. Only a socket
        // file deleted by hand while the app ran lets another copy put its
        // own there. Compare the inode from bind if that ever matters.
        unlink(path)
    }

    /// Removes a socket a copy of this build that crashed left behind. A
    /// socket another running copy listens on, and anything that is not a
    /// socket, are left alone, and opening fails.
    ///
    /// ponytail: two copies starting in the same instant can both find no
    /// listener, and the second's `bind` then fails with `EADDRINUSE`.
    private func removeLeftover(at address: UnixSocketAddress) throws {
        var status = stat()
        guard lstat(path, &status) == 0 else { return }
        guard status.st_mode & S_IFMT == S_IFSOCK else { throw HookSocketError.notASocket }
        let probe = try check("socket", Darwin.socket(AF_UNIX, SOCK_DGRAM, 0))
        defer { close(probe) }
        guard address.withSocketAddress({ connect(probe, $0, $1) }) != 0 else { throw HookSocketError.inUse }
        guard errno == ECONNREFUSED else { throw HookSocketError.system(call: "connect", code: errno) }
        try check("unlink", unlink(path))
    }

    /// `result` of the system call named `call`, or its `errno` as an error when it failed.
    @discardableResult
    private func check(_ call: String, _ result: Int32) throws -> Int32 {
        guard result != -1 else { throw HookSocketError.system(call: call, code: errno) }
        return result
    }

    /// A source that reads `socket` on a queue of its own, off the main thread.
    ///
    /// `nonisolated`, so its handlers are not taken as the main actor's and
    /// run on that queue.
    private nonisolated static func readSource(
        of socket: Int32,
        receive: @escaping @MainActor (Data, Date) -> Void,
    ) -> any DispatchSourceRead {
        let source = DispatchSource.makeReadSource(fileDescriptor: socket, queue: DispatchQueue(label: "hook-socket"))
        source.setEventHandler {
            var buffer = [UInt8](repeating: 0, count: HookEvent.maximumSize + 1)
            // Until the socket is empty, which a non-blocking recv reports as EAGAIN.
            while case let count = recv(socket, &buffer, buffer.count, 0), count >= 0 {
                let message = Data(buffer[..<count])
                let arrival = Date.now
                // The main queue keeps the order the messages came in.
                DispatchQueue.main.async { receive(message, arrival) }
            }
        }
        source.setCancelHandler { close(socket) }
        return source
    }
}
