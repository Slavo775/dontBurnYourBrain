import AppKit
import CoreServices
import DontBurnCore
import Observation
import os

/// Brings a session's own tab forward in the terminal that holds it. One
/// adapter per terminal.
protocol TerminalFocusing: Sendable {
    /// The terminal it brings forward.
    var terminal: TerminalApp { get }

    /// Brings `session`'s tab forward. macOS asks the user for Automation
    /// first when it has not asked for this terminal yet. Sends nothing for a
    /// tab that is gone.
    func focus(_ session: AgentSession) async -> FocusOutcome
}

/// iTerm2: the session by the unique ID the hook reported. A UUID is never
/// given to another session, so it needs no other check.
struct ITerm2Focus: TerminalFocusing {
    let terminal = TerminalApp.iTerm2

    func focus(_ session: AgentSession) async -> FocusOutcome {
        guard case let .iTerm2(sessionID)? = session.focusHandle else { return .gone }
        if let refusal = await AppleEvents.askToControl(terminal) {
            return refusal
        }
        return await AppleEvents.call(Self.script, handler: "focussession", with: sessionID)
    }

    /// Selects the window, the tab and the session, un-minimizing the window
    /// when needed, and activates iTerm2. Reads only the unique ID of other
    /// sessions. Answers whether it found the session.
    private static let script = """
    on focussession(target)
        if application id "com.googlecode.iterm2" is not running then return false
        tell application id "com.googlecode.iterm2"
            with timeout of 5 seconds
                repeat with winId in (get id of windows)
                    set idsPerTab to unique ID of sessions of tabs of window id winId
                    repeat with t from 1 to count of idsPerTab
                        set ids to item t of idsPerTab
                        repeat with s from 1 to count of ids
                            if item s of ids is target then
                                set w to window id winId
                                if miniaturized of w then set miniaturized of w to false
                                select w
                                select tab t of w
                                select session s of tab t of w
                                activate
                                return true
                            end if
                        end repeat
                    end repeat
                end repeat
            end timeout
        end tell
        return false
    end focussession
    """
}

/// Terminal: the tab by its tty, and only while the session's `claude`
/// process still holds that tty, because a closed tab's tty goes to the next
/// tab at once.
struct TerminalTabFocus: TerminalFocusing {
    let terminal = TerminalApp.terminal

    func focus(_ session: AgentSession) async -> FocusOutcome {
        guard case let .terminal(tty)? = session.focusHandle, session.stillHoldsTTY(lookingUp: Self.tty) else {
            return .gone
        }
        if let refusal = await AppleEvents.askToControl(terminal) {
            return refusal
        }
        // Again, since the user may have taken a while over the prompt.
        guard session.stillHoldsTTY(lookingUp: Self.tty) else { return .gone }
        return await AppleEvents.call(Self.script, handler: "focustty", with: "/dev/" + tty)
    }

    private static func tty(ofProcess processID: Int32) -> String? {
        TerminalDevice.name(ofProcess: processID)
    }

    /// Selects the tab, brings its window to the front, un-minimizing it when
    /// needed, and activates Terminal. Each tab is a window of its own in
    /// Terminal's AppleScript. Reads only the tty of other tabs. Answers
    /// whether it found the tab.
    private static let script = """
    on focustty(target)
        if application id "com.apple.Terminal" is not running then return false
        tell application id "com.apple.Terminal"
            with timeout of 5 seconds
                repeat with winId in (get id of windows)
                    set ttys to tty of tabs of window id winId
                    repeat with i from 1 to count of ttys
                        if item i of ttys is target then
                            set w to window id winId
                            if miniaturized of w then set miniaturized of w to false
                            set selected of tab i of w to true
                            set index of w to 1
                            activate
                            return true
                        end if
                    end repeat
                end repeat
            end timeout
        end tell
        return false
    end focustty
    """
}

/// The Apple events the adapters send. Each can block, so each runs off the main actor.
enum AppleEvents {
    // AppleScript's codes for calling a handler, from Carbon's ASRegistry.h,
    // which is not worth importing Carbon for: 'ascr', 'psbr' and 'snam'.
    private static let appleScriptSuite: AEEventClass = 0x6173_6372
    private static let subroutineEvent: AEEventID = 0x7073_6272
    private static let subroutineName: AEKeyword = 0x736E_616D

    /// Whether macOS lets the app control `terminal`. With `asking`, macOS
    /// asks the user when it has no answer yet, and this waits for it.
    @concurrent
    nonisolated static func permission(for terminal: TerminalApp, asking: Bool) async -> AutomationPermission {
        AutomationPermission(status: status(for: terminal, asking: asking))
    }

    /// `nil` when the app may control `terminal`, asking the user first when
    /// macOS has not asked yet, otherwise why nothing is sent.
    @concurrent
    nonisolated static func askToControl(_ terminal: TerminalApp) async -> FocusOutcome? {
        let status = status(for: terminal, asking: true)
        switch AutomationPermission(status: status) {
        case .allowed: return nil
        case .denied: return .denied
        case .notRunning: return .gone
        case .notAsked, .unknown: return .failed(Int(status))
        }
    }

    /// Blocks while macOS asks the user, and answers `procNotFound` for a terminal that is not running.
    private nonisolated static func status(for terminal: TerminalApp, asking: Bool) -> Int32 {
        let target = NSAppleEventDescriptor(bundleIdentifier: terminal.rawValue)
        return withExtendedLifetime(target) {
            guard let address = target.aeDesc else { return -600 }
            return AEDeterminePermissionToAutomateTarget(address, typeWildCard, typeWildCard, asking)
        }
    }

    /// Calls `handler` in `source` with `argument`, which goes in as an Apple
    /// event parameter, never into the script's text.
    @concurrent
    nonisolated static func call(_ source: String, handler: String, with argument: String) async -> FocusOutcome {
        guard let script = NSAppleScript(source: source) else { return .failed(0) }
        let call = NSAppleEventDescriptor(
            eventClass: appleScriptSuite,
            eventID: subroutineEvent,
            targetDescriptor: nil,
            returnID: AEReturnID(kAutoGenerateReturnID),
            transactionID: AETransactionID(kAnyTransactionID),
        )
        // AppleScript keeps a handler's name in lowercase.
        call.setParam(NSAppleEventDescriptor(string: handler.lowercased()), forKeyword: subroutineName)
        let arguments = NSAppleEventDescriptor.list()
        arguments.insert(NSAppleEventDescriptor(string: argument), at: 0)
        call.setParam(arguments, forKeyword: AEKeyword(keyDirectObject))
        var error: NSDictionary?
        let result = script.executeAppleEvent(call, error: &error)
        let number = (error?[NSAppleScript.errorNumber] as? NSNumber)?.intValue
        // A script that failed to compile names no number.
        return FocusOutcome(found: result.booleanValue, errorNumber: error == nil ? nil : number ?? 0)
    }
}

/// Brings sessions' tabs forward, and knows which terminals macOS lets the app control.
///
/// It asks macOS for Automation only when Focus is pressed, once per
/// terminal, and reads the answer without asking when the sessions or
/// Settings show. With the sample data it sends no Apple event and reads
/// nothing: every terminal reads as allowed, and Focus does nothing.
@MainActor
@Observable
final class TerminalFocus {
    /// The terminals with an adapter, in the order Settings lists them.
    static let terminals: [TerminalApp] = [.iTerm2, .terminal]

    /// Each terminal's permission as last read.
    private(set) var permissions: [TerminalApp: AutomationPermission] = [:]

    private let adapters: [TerminalApp: any TerminalFocusing]
    private let isSample: Bool
    private let log = Logger(subsystem: Bundle.main.bundleIdentifier ?? "", category: "focus")

    init(isSample: Bool) {
        self.isSample = isSample
        let adapters: [any TerminalFocusing] = [ITerm2Focus(), TerminalTabFocus()]
        self.adapters = Dictionary(uniqueKeysWithValues: adapters.map { ($0.terminal, $0) })
        if isSample {
            permissions = Dictionary(uniqueKeysWithValues: Self.terminals.map { ($0, .allowed) })
        }
    }

    /// The terminals macOS refused the app, whose sessions get no Focus button.
    var denied: Set<TerminalApp> {
        Set(permissions.compactMap { $0.value == .denied ? $0.key : nil })
    }

    /// `terminal`'s permission as last read.
    func permission(of terminal: TerminalApp) -> AutomationPermission {
        permissions[terminal] ?? .unknown
    }

    /// Reads each terminal's permission again, without asking the user.
    func readPermissions() async {
        guard !isSample else { return }
        for terminal in Self.terminals {
            permissions[terminal] = await AppleEvents.permission(for: terminal, asking: false)
        }
    }

    /// Brings `session`'s tab forward. Nothing is sent while the screen is locked.
    func focus(_ session: AgentSession) async -> FocusOutcome {
        guard let terminal = session.focusHandle?.terminal, let adapter = adapters[terminal] else { return .notSent }
        guard !isSample else {
            log.info("Focus with the sample data sends nothing")
            return .notSent
        }
        // While it is locked, activating a terminal blocks for about 2 s and brings nothing forward.
        guard !Self.isScreenLocked else {
            log.info("Focus while the screen is locked sends nothing")
            return .notSent
        }
        let outcome = await adapter.focus(session)
        switch outcome {
        case .focused: permissions[terminal] = .allowed
        case .denied: permissions[terminal] = .denied
        case .gone, .timedOut, .notSent, .failed: break
        }
        log.info("Focus in \(terminal.name, privacy: .public): \(String(describing: outcome), privacy: .public)")
        return outcome
    }

    private static var isScreenLocked: Bool {
        let session = CGSessionCopyCurrentDictionary() as? [String: Any]
        return session?["CGSSessionScreenIsLocked"] as? Bool == true
    }
}
