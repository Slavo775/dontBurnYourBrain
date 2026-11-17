// Spike helper for card #6. Not part of the app and not built by the check. See README.md.
//   swift focus-check.swift focus   <terminal|iterm2> <A|B> <folder> [seconds to wait first]
//   swift focus-check.swift measure <terminal|iterm2> <folder> [attempts per tab, default 10]
//   swift focus-check.swift case    <terminal|iterm2> <minimized|gone> <folder> [attempts, default 3]
// <folder> holds the files open-tabs.sh wrote. Right means the frontmost app, the terminal's AppleScript
// and the window server's order agree. Output names tabs A, B or other, never a handle, title or app.
import AppKit

enum TerminalApp: String {
    case terminal, iterm2

    var bundleID: String {
        self == .terminal ? "com.apple.Terminal" : "com.googlecode.iterm2"
    }

    var scriptName: String {
        self == .terminal ? "Terminal" : "iTerm2"
    }

    /// The other terminal, put in front before each attempt as "the app the user works in".
    var other: TerminalApp {
        self == .terminal ? .iterm2 : .terminal
    }

    var focusScript: String {
        here + (self == .terminal ? "/focus-terminal.applescript" : "/focus-iterm2.applescript")
    }

    /// {frontmost, front window id, handle of that window's selected tab}
    var frontQuery: String {
        switch self {
        case .terminal:
            "tell application \"Terminal\" to get {frontmost, id of front window, tty of selected tab of front window}"
        case .iterm2:
            "tell application \"iTerm2\" to get "
                + "{frontmost, id of current window, unique ID of current session of current window}"
        }
    }
}

struct Attempt {
    var right: Bool
    var focus: Double
    var agree: Double
}

struct Signals {
    var frontApp = "other"
    var scriptFrontmost = false
    var scriptWindow = 0
    var scriptHandle = ""
    var serverTopIsTerminal = false
    var serverTopWindow = 0

    func agree(on handle: String) -> Bool {
        frontApp == app.rawValue && scriptFrontmost && scriptHandle == handle
            && serverTopIsTerminal && serverTopWindow == scriptWindow
    }

    var line: String {
        "front=\(frontApp) script=\(scriptFrontmost ? "frontmost" : "background"),tab \(label(scriptHandle))"
            + ",window \([windowA, windowB].contains(scriptWindow) ? "spike" : "other")"
            + " server=\(serverTopIsTerminal ? app.rawValue : "other")"
            + (serverTopIsTerminal ? ",window \(serverTopWindow == scriptWindow ? "same" : "different")" : "")
    }
}

let here = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent().path
let args = Array(CommandLine.arguments.dropFirst())
let app: TerminalApp = {
    guard args.count >= 3, let app = TerminalApp(rawValue: args[1]) else {
        fail("usage: see the top of focus-check.swift")
    }
    return app
}()

if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true {
    fail("The screen is locked, so the login window is the frontmost app. Unlock it first.")
}

let terminalPid = NSRunningApplication.runningApplications(withBundleIdentifier: app.bundleID).first?.processIdentifier
let folder = args[args[0] == "measure" ? 2 : 3]
let handleA = handle(in: "\(folder)/\(app.rawValue)-A")
let handleB = handle(in: "\(folder)/\(app.rawValue)-B")
let frontQueryScript = NSAppleScript(source: app.frontQuery)
let windowA = windowHolding(handleA)
let windowB = windowHolding(handleB)
if windowA == 0 || windowB == 0 {
    fail("No \(app.scriptName) tab holds the handle in \(windowA == 0 ? "A" : "B"). Open new spike tabs.")
}

switch args[0] {
case "focus":
    let target = args[2] == "B" ? handleB : handleA
    // Time to click another app, so the focus starts from there as it will from the menu bar.
    if args.count > 4, let wait = Double(args[4]) {
        print("Focus in \(Int(wait)) seconds. Click a window of another app now.")
        RunLoop.current.run(until: Date(timeIntervalSinceNow: wait))
    }
    attempt(to: target, label: args[2])
    print(order())
case "measure":
    measure(attempts: args.count > 3 ? Int(args[3]) ?? 10 : 10)
case "case":
    awkward(args[2], attempts: args.count > 4 ? Int(args[4]) ?? 3 : 3)
default:
    fail("usage: see the top of focus-check.swift")
}

func currentSignals() -> Signals {
    var signals = Signals()
    // From LaunchServices, not NSWorkspace: a command-line process sees NSWorkspace's
    // frontmost app change only while its run loop delivers the notifications.
    let front = run("/usr/bin/lsappinfo", ["info", "-only", "bundleid", run("/usr/bin/lsappinfo", ["front"]).message])
    let bundleLine = front.message.split(separator: "\n")
        .first { $0.contains("bundleID=") || $0.contains("CFBundleIdentifier") }
    switch bundleLine?.split(separator: "\"").last.map(String.init) {
    case TerminalApp.terminal.bundleID: signals.frontApp = TerminalApp.terminal.rawValue
    case TerminalApp.iterm2.bundleID: signals.frontApp = TerminalApp.iterm2.rawValue
    default: signals.frontApp = "other"
    }
    var error: NSDictionary?
    if let result = frontQueryScript?.executeAndReturnError(&error), result.numberOfItems == 3 {
        signals.scriptFrontmost = result.atIndex(1)?.booleanValue ?? false
        signals.scriptWindow = Int(result.atIndex(2)?.int32Value ?? 0)
        signals.scriptHandle = result.atIndex(3)?.stringValue ?? ""
    }
    // The topmost window over the front window's spot. Not simply the topmost window: with
    // several displays, a window elsewhere can be higher in the list without covering it.
    let windows = onScreenWindows()
    let frontWindow = windows.first { $0.number == signals.scriptWindow }
    if let frontWindow, let top = windows.first(where: { $0.bounds.intersects(frontWindow.bounds) }) {
        signals.serverTopIsTerminal = top.pid == terminalPid
        signals.serverTopWindow = top.number
    }
    return signals
}

struct ScreenWindow {
    var pid: pid_t
    var number: Int
    var bounds: CGRect
}

/// Normal windows (layer 0) that are on screen, front to back. Without Screen Recording
/// permission the list has no window names, and none are read here.
func onScreenWindows() -> [ScreenWindow] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID)
        as? [[String: Any]] ?? []
    return list.compactMap { info in
        guard info[kCGWindowLayer as String] as? Int == 0,
              (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let number = info[kCGWindowNumber as String] as? Int,
              let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                  .flatMap({ CGRect(dictionaryRepresentation: $0) })
        else { return nil }
        return ScreenWindow(pid: pid, number: number, bounds: bounds)
    }
}

/// How many of the terminal's on-screen windows no window of another app covers, even in part.
/// Only windows its AppleScript knows count, so tab bars and other helper windows are left out.
func order() -> String {
    let ids = Set(osascript(["-e", "tell application \"\(app.scriptName)\" to get id of windows"]).message
        .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    let windows = onScreenWindows()
    let mine = windows.enumerated().filter { $0.element.pid == terminalPid && ids.contains($0.element.number) }
    let uncovered = mine.filter { index, window in
        !windows[..<index].contains { $0.pid != terminalPid && $0.bounds.intersects(window.bounds) }
    }
    return "order: \(uncovered.count) of \(mine.count) on-screen \(app.scriptName) windows "
        + "are covered by no window of another app"
}

/// Runs the focus command once, then reads the signals until they agree or 3 seconds pass.
@discardableResult
func attempt(to target: String, label: String, prefix: String = "") -> Attempt {
    let start = ContinuousClock.now
    let (status, message) = osascript([app.focusScript, target])
    let focus = seconds(ContinuousClock.now - start)
    var signals = currentSignals()
    var readings = 1
    while !signals.agree(on: target), ContinuousClock.now - start < .seconds(3) {
        signals = currentSignals()
        readings += 1
    }
    let agree = seconds(ContinuousClock.now - start)
    let right = signals.agree(on: target)
    print(prefix + "\(app.rawValue) → \(label): \(right ? "RIGHT" : "WRONG") exit=\(status)"
        + " focus=\(format(focus)) agree=\(right ? format(agree) : "never") readings=\(readings) \(signals.line)"
        + (status == 0 ? "" : " message=\"\(message)\""))
    return Attempt(right: right, focus: focus, agree: agree)
}

/// Selects the other spike tab and puts the other terminal in front, so each attempt starts
/// the way the Focus button will be used: from the menu bar while the user works elsewhere.
/// Stops the run when that starting state is not reached, and returns it for the result line.
@discardableResult
func setScene(otherTab: String) -> String {
    let selected = osascript([app.focusScript, otherTab])
    guard selected.status == 0 else { fail("Could not select tab \(label(otherTab)): \(selected.message)") }
    _ = osascript(["-e", "tell application \"\(app.other.scriptName)\" to activate"])
    var signals = currentSignals()
    let ready = waitFor {
        signals = currentSignals()
        return signals.frontApp == app.other.rawValue && signals.scriptHandle == otherTab
    }
    guard ready else { fail("The starting state was not reached: \(signals.line)") }
    return "from=\(signals.frontApp),tab \(label(signals.scriptHandle)) "
}

func measure(attempts: Int) {
    var results: [Attempt] = []
    for (target, label, otherTab) in [(handleA, "A", handleB), (handleB, "B", handleA)] {
        for index in 1 ... attempts {
            let scene = setScene(otherTab: otherTab)
            results.append(attempt(to: target, label: label, prefix: "\(label) \(index)/\(attempts) \(scene)"))
        }
    }
    print(order())
    for (label, part) in [("A", results.prefix(attempts)), ("B", results.suffix(attempts))] {
        print("summary \(app.rawValue) → \(label): \(part.filter(\.right).count) of \(attempts) right")
    }
    summarize(results)
}

func awkward(_ name: String, attempts: Int) {
    if name == "minimized" {
        requireSpikeOnlyWindow()
    }
    if name == "gone", app == .terminal, windowHolding("/dev/ttys999") != 0 {
        fail("A Terminal tab holds /dev/ttys999, so it cannot stand for a tab that is gone.")
    }
    var results: [Attempt] = []
    for index in 1 ... attempts {
        let prefix = "\(name) \(index)/\(attempts) "
        switch name {
        case "minimized":
            // Minimize the spike window while tab B is selected, so A is a background tab in it.
            let selected = osascript([app.focusScript, handleB])
            guard selected.status == 0 else { fail("Could not select tab B: \(selected.message)") }
            let minimize = "set miniaturized of window id \(windowB) to true"
            _ = osascript(["-e", "tell application \"\(app.scriptName)\" to \(minimize)"])
            guard waitFor({ !onScreenWindows().contains { $0.number == windowB } }) else {
                fail("The spike window did not leave the screen when minimized.")
            }
            _ = osascript(["-e", "tell application \"\(app.other.scriptName)\" to activate"])
            guard waitFor({ currentSignals().frontApp == app.other.rawValue }) else {
                fail("\(app.other.scriptName) did not come to the front.")
            }
            results.append(attempt(to: handleA, label: "A, window minimized", prefix: prefix + "from=minimized "))
        case "gone":
            let gone = app == .terminal ? "/dev/ttys999" : UUID().uuidString
            setScene(otherTab: handleB)
            let before = currentSignals().line
            let start = ContinuousClock.now
            let (status, message) = osascript([app.focusScript, gone])
            let took = seconds(ContinuousClock.now - start)
            RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.3))
            let after = currentSignals().line
            print(prefix + "\(app.rawValue) → a tab that does not exist: exit=\(status) took=\(format(took))"
                + " message=\"\(message.replacingOccurrences(of: gone, with: "<handle>"))\""
                + " changed=\(before == after ? "nothing" : "yes: \(before) → \(after)")")
        default:
            fail("the cases are minimized and gone")
        }
    }
    if !results.isEmpty {
        print(order())
        print("summary \(app.rawValue) \(name): \(results.filter(\.right).count) of \(attempts) right")
        summarize(results)
    }
}

func summarize(_ results: [Attempt]) {
    let focus = results.map(\.focus).sorted()
    let agree = results.filter(\.right).map(\.agree).sorted()
    print("timing: focus command median \(format(median(focus))), worst \(format(focus.last ?? 0));"
        + " signals agree median \(format(median(agree))), worst \(format(agree.last ?? 0))")
}

func osascript(_ arguments: [String]) -> (status: Int32, message: String) {
    run("/usr/bin/osascript", arguments)
}

func run(_ tool: String, _ arguments: [String]) -> (status: Int32, message: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    let output = Pipe()
    process.standardOutput = output
    process.standardError = output
    do { try process.run() } catch { fail("\(tool) did not start: \(error)") }
    process.waitUntilExit()
    var text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    // osascript puts the script's path in front of an error. Keep only the script's own words.
    if let range = text.range(of: "execution error: ") {
        text = String(text[range.upperBound...])
    }
    return (process.terminationStatus, text.trimmingCharacters(in: .whitespacesAndNewlines))
}

func handle(in file: String) -> String {
    guard let text = try? String(contentsOfFile: file, encoding: .utf8) else {
        fail("\(file) is missing. Run open-tabs.sh \(app.rawValue) <folder> first")
    }
    let values = Dictionary(text.split(separator: "\n").map { line in
        let parts = line.split(separator: "=", maxSplits: 1).map(String.init)
        return (parts[0], parts.count > 1 ? parts[1] : "")
    }, uniquingKeysWith: { first, _ in first })
    let value = app == .terminal ? values["tty"] : values["iterm"]?.split(separator: ":").last.map(String.init)
    guard let value, !value.isEmpty else { fail("\(file) holds no handle") }
    // A tty goes to the next tab that opens once its tab closes. Trust it only while the
    // spike tab's shell still holds it, so a stale folder never moves someone else's tab.
    // An iTerm2 unique ID is never reused, so it needs no such check.
    if app == .terminal {
        let pid = values["pid"].flatMap { Int32($0) } ?? 0
        let held = run("/bin/ps", ["-o", "tty=", "-p", String(pid)]).message
        guard pid > 0, "/dev/" + held == value else {
            fail("\(file): the shell that held this tty is gone, so the tab may be someone else's."
                + " Open new spike tabs with open-tabs.sh.")
        }
    }
    return value
}

func windowHolding(_ handle: String) -> Int {
    let source = app == .terminal
        ? """
        tell application "Terminal"
            repeat with winId in (get id of windows)
                if (tty of tabs of window id winId) contains "\(handle)" then return winId as integer
            end repeat
        end tell
        """
        : """
        tell application "iTerm2"
            repeat with winId in (get id of windows)
                repeat with ids in (get unique ID of sessions of tabs of window id winId)
                    if ids contains "\(handle)" then return winId as integer
                end repeat
            end repeat
        end tell
        """
    return Int(osascript(["-e", source]).message) ?? 0
}

func label(_ handle: String) -> String {
    handle == handleA ? "A" : handle == handleB ? "B" : handle.isEmpty ? "none" : "other"
}

/// Checks the condition until it holds or 3 seconds pass, and says whether it held.
@discardableResult
func waitFor(_ condition: () -> Bool) -> Bool {
    let start = ContinuousClock.now
    while !condition() {
        guard ContinuousClock.now - start < .seconds(3) else { return false }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }
    return true
}

/// Minimizing a window takes all of its tabs along. Stops unless the spike window holds only
/// tabs A and B, so the case never minimizes a tab that is not the spike's. In Terminal a tab
/// is a window of its own, and the tabs of one window share its bounds.
func requireSpikeOnlyWindow() {
    let source = app == .terminal
        ? """
        tell application "Terminal"
            set spikeBounds to bounds of window id \(windowB)
            if bounds of window id \(windowA) is not spikeBounds then return 0
            return count (windows whose bounds is spikeBounds)
        end tell
        """
        : "tell application \"iTerm2\" to return count of tabs of window id \(windowB)"
    let tabs = Int(osascript(["-e", source]).message) ?? 0
    guard tabs == 2, app == .terminal || windowA == windowB else {
        fail("The spike window does not hold exactly tabs A and B, so minimizing it could take other tabs along.")
    }
}

func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let middle = values.count / 2
    return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
}

func format(_ value: Double) -> String {
    String(format: "%.3fs", value)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}
