import Foundation

// The Focus button's rules. The handles come from the hook's event channel,
// from outside the app, so only the shape a terminal itself gives out is
// taken, and a Terminal tty only while the session's process still holds it.
// The Apple events are sent by the app, in `Apps/Mac/TerminalFocus.swift`.

/// What the Focus button finds a session's tab by.
public enum FocusHandle: Equatable, Sendable {
    /// iTerm2's unique ID of the session, a UUID.
    case iTerm2(sessionID: String)
    /// The name of the tab's tty in Terminal, such as `ttys004`.
    case terminal(tty: String)

    /// The terminal app the handle belongs to.
    public var terminal: TerminalApp {
        switch self {
        case .iTerm2: .iTerm2
        case .terminal: .terminal
        }
    }

    /// Whether `name` is the name macOS gives a terminal tab's tty: `ttys`
    /// and three ASCII digits, as `devname` returns it. macOS gives out at
    /// most 999 of them.
    public static func isTTYName(_ name: String) -> Bool {
        let bytes = Array(name.utf8)
        return bytes.count == 7 && name.hasPrefix("ttys")
            && bytes.dropFirst(4).allSatisfy { (UInt8(ascii: "0") ... UInt8(ascii: "9")).contains($0) }
    }
}

public extension AgentSession {
    /// The handle the Focus button brings the session's tab forward by, or
    /// `nil` when the session gets no Focus button: its terminal is neither
    /// Terminal nor iTerm2, or the hook sent no handle of the right shape for it.
    ///
    /// Checked here, where it is used, so a session read back from the file is checked too.
    var focusHandle: FocusHandle? {
        switch terminalBundleIdentifier.flatMap(TerminalApp.init(rawValue:)) {
        case .iTerm2: tabID.flatMap { UUID(uuidString: $0) == nil ? nil : .iTerm2(sessionID: $0) }
        case .terminal: tty.flatMap { FocusHandle.isTTYName($0) ? .terminal(tty: $0) : nil }
        case .visualStudioCode, .cursor, nil: nil
        }
    }

    /// Whether the session's `claude` process still runs and still holds the
    /// tty the session recorded, as `ttyOfProcess` reads it.
    ///
    /// A tty goes to a new tab as soon as its own closes, so Terminal is never
    /// sent a tty without this. A process that is gone has no tty.
    ///
    /// ponytail: a process ID given to a new process in a tab that got the same
    /// tty passes. Compare the process's start time when that matters.
    func stillHoldsTTY(lookingUp ttyOfProcess: (Int32) -> String?) -> Bool {
        guard processID > 0, let tty else { return false }
        return ttyOfProcess(processID) == tty
    }
}

/// The controlling terminal of a process.
public enum TerminalDevice {
    /// The name of the tty of process `processID`, such as `ttys004`, or `nil`
    /// when it has none or is gone. One `sysctl` call, not a list of every process.
    public static func name(ofProcess processID: Int32) -> String? {
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
}

/// Whether macOS lets the app send a terminal Apple events.
public enum AutomationPermission: Equatable, Sendable {
    /// The user allowed it.
    case allowed
    /// The user refused it. Only System Settings can change that.
    case denied
    /// macOS has not asked the user yet.
    case notAsked
    /// The terminal is not running, so macOS cannot tell.
    case notRunning
    /// Not read yet, or an answer the app does not know.
    case unknown

    /// The permission `status` says, as `AEDeterminePermissionToAutomateTarget` returns it.
    public init(status: Int32) {
        switch status {
        case 0: self = .allowed
        // errAEEventNotPermitted
        case -1743: self = .denied
        // errAEEventWouldRequireUserConsent
        case -1744: self = .notAsked
        // procNotFound
        case -600: self = .notRunning
        default: self = .unknown
        }
    }
}

/// What came of pressing Focus.
public enum FocusOutcome: Equatable, Sendable {
    /// The tab came forward.
    case focused
    /// The tab is gone: no tab holds the handle, the session's process no
    /// longer holds its tty, or the terminal is not running. Nothing was brought forward.
    case gone
    /// macOS does not let the app control the terminal.
    case denied
    /// The terminal did not answer in time, usually because a dialog is open on screen.
    case timedOut
    /// Nothing was sent: the screen is locked, the session has no handle, or
    /// the sample data is shown.
    case notSent
    /// Another Apple event error, by its number.
    case failed(Int)

    /// The outcome of a focus script that answered whether it `found` the
    /// tab, or failed with the Apple event error `errorNumber`.
    public init(found: Bool, errorNumber: Int?) {
        switch errorNumber {
        case nil: self = found ? .focused : .gone
        // errAEEventNotPermitted
        case -1743: self = .denied
        // errAETimeout
        case -1712: self = .timedOut
        // procNotFound and connectionInvalid: the terminal is not running, or quit meanwhile.
        case -600, -609: self = .gone
        case let number?: self = .failed(number)
        }
    }
}
