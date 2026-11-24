import Darwin
import DontBurnCore
import Foundation

// Claude Code runs this tool as a hook, with one event on standard input. It
// sends the trimmed event to the running app and is gone. In hook mode it
// prints nothing, because Claude Code puts what a hook prints into the
// session's context, and it always exits 0 at once, so a session never waits
// for the app or fails because of it. See "Release and Dev" in
// docs/spikes/claude-hook.md.

let arguments = Array(CommandLine.arguments.dropFirst())
/// The Info.plist built into the binary: the tool's version, and the app's
/// two bundle identifiers, all from project.yml.
let info = Bundle.main.infoDictionary ?? [:]

if arguments.contains("--version") {
    let version = info["CFBundleShortVersionString"] as? String ?? "unknown"
    let build = info["CFBundleVersion"] as? String ?? "unknown"
    print("dontburn-hook \(version) (\(build))")
    exit(0)
}

/// The name of the tty of process `processID`, such as `ttys004`, or `nil`
/// when it has none. One `sysctl` call, not a list of every process.
func terminalName(ofProcess processID: Int32) -> String? {
    var process = kinfo_proc()
    var size = MemoryLayout<kinfo_proc>.stride
    var name = [CTL_KERN, KERN_PROC, KERN_PROC_PID, processID]
    // A process that is gone leaves the size at 0.
    guard sysctl(&name, u_int(name.count), &process, &size, nil, 0) == 0, size > 0 else { return nil }
    let device = process.kp_eproc.e_tdev
    // NODEV, (dev_t)-1, which Swift does not import.
    guard device != -1, let path = devname(device, S_IFCHR) else { return nil }
    return String(cString: path)
}

/// Sends `message` to the socket at `address` without waiting. Every failure,
/// such as no app listening, is ignored: the event is simply lost.
func send(_ message: Data, to address: UnixSocketAddress) {
    let socket = Darwin.socket(AF_UNIX, SOCK_DGRAM, 0)
    guard socket >= 0 else { return }
    defer { close(socket) }
    // A datagram may not be larger than the send buffer, 2048 bytes by default.
    var bufferSize = Int32(HookEvent.maximumSize)
    setsockopt(socket, SOL_SOCKET, SO_SNDBUF, &bufferSize, socklen_t(MemoryLayout<Int32>.size))
    _ = message.withUnsafeBytes { bytes in
        address.withSocketAddress { sendto(socket, bytes.baseAddress, bytes.count, MSG_DONTWAIT, $0, $1) }
    }
}

let environment = ProcessInfo.processInfo.environment
// Every failure ends the same way, with nothing sent and exit status 0, so each `try?` is enough.
guard let target = HookTarget(arguments: arguments, environment: environment),
      let bundleIdentifier = target.bundleIdentifier(in: info),
      // One byte more than the limit tells an event that is too large without reading all of it.
      let input = try? FileHandle.standardInput.read(upToCount: HookEvent.maximumClaudeEventSize + 1),
      let event = try? HookEvent(claudeEvent: input, environment: environment, tty: terminalName(ofProcess:)),
      let message = try? JSONEncoder().encode(event),
      let address = try? UnixSocketAddress(path: HookChannel.url(
          bundleIdentifier: bundleIdentifier,
          applicationSupport: .applicationSupportDirectory,
      ).path(percentEncoded: false))
else { exit(0) }
send(message, to: address)
exit(0)
