// Spike helper for card #6. Not part of the app and not built by the check.
//
//   swift focus-check.swift signals <terminal|iterm2> <folder>
//   swift focus-check.swift focus   <terminal|iterm2> <A|B> <folder> [seconds to wait first]
//   swift focus-check.swift measure <terminal|iterm2> <folder> [attempts per tab, default 10]
//   swift focus-check.swift case    <terminal|iterm2> <minimized|gone> <folder> [attempts, default 3]
//
// A hidden app is a hand step (Cmd-H): NSRunningApplication.hide() returns false for
// another app when called from here, and every other way needs a new permission.
//
// <folder> holds the files open-tabs.sh wrote. An attempt is right only when three
// independent signals agree: the frontmost app, the terminal's own AppleScript (its
// front window and that window's selected tab), and the window server's on-screen
// order. Output names tabs as A, B or other, never a handle, a title or another app.
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

    var pid: pid_t? {
        NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.processIdentifier
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

let folder = args[args[0] == "signals" || args[0] == "measure" ? 2 : 3]
let handleA = handle(in: "\(folder)/\(app.rawValue)-A")
let handleB = handle(in: "\(folder)/\(app.rawValue)-B")
let frontQueryScript = NSAppleScript(source: app.frontQuery)
// iTerm2 shows its tabs inside one AppleScript window. Terminal shows each tab of a
// window's tab bar as an AppleScript window of its own, with one tab.
let windowA = windowHolding(handleA)
let windowB = windowHolding(handleB)

switch args[0] {
case "signals":
    let clock = ContinuousClock()
    let start = clock.now
    let signals = currentSignals()
    print(signals.line + " took=\(format(seconds(clock.now - start)))")
    print(order())
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

// MARK: - Signals

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
        signals.serverTopIsTerminal = top.pid == app.pid
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
    let ids = Set(runScript("tell application \"\(app.scriptName)\" to get id of windows")
        .split(separator: ",").compactMap { Int($0.trimmingCharacters(in: .whitespaces)) })
    let windows = onScreenWindows()
    let mine = windows.enumerated().filter { $0.element.pid == app.pid && ids.contains($0.element.number) }
    let uncovered = mine.filter { index, window in
        !windows[..<index].contains { $0.pid != app.pid && $0.bounds.intersects(window.bounds) }
    }
    return "order: \(uncovered.count) of \(mine.count) on-screen \(app.scriptName) windows "
        + "are covered by no window of another app"
}

// MARK: - Attempts

/// Runs the focus command once, then reads the signals until they agree or 3 seconds pass.
@discardableResult
func attempt(to target: String, label: String, prefix: String = "") -> Attempt {
    let clock = ContinuousClock()
    let start = clock.now
    let (status, message) = osascript([app.focusScript, target])
    let focus = seconds(clock.now - start)
    var signals = currentSignals()
    var readings = 1
    while !signals.agree(on: target), clock.now - start < .seconds(3) {
        signals = currentSignals()
        readings += 1
    }
    let agree = seconds(clock.now - start)
    let right = signals.agree(on: target)
    print(prefix + "\(app.rawValue) → \(label): \(right ? "RIGHT" : "WRONG") exit=\(status)"
        + " focus=\(format(focus)) agree=\(right ? format(agree) : "never") readings=\(readings) \(signals.line)"
        + (status == 0 ? "" : " message=\"\(message)\""))
    return Attempt(right: right, focus: focus, agree: agree)
}

/// Selects the other spike tab and puts the other terminal in front, so each attempt starts
/// the way the Focus button will be used: from the menu bar while the user works elsewhere.
func setScene(otherTab: String) {
    _ = osascript([app.focusScript, otherTab])
    _ = osascript(["-e", "tell application \"\(app.other.scriptName)\" to activate"])
    let clock = ContinuousClock()
    let start = clock.now
    while currentSignals().frontApp != app.other.rawValue, clock.now - start < .seconds(2) {}
}

func measure(attempts: Int) {
    var results: [Attempt] = []
    for (target, label, otherTab) in [(handleA, "A", handleB), (handleB, "B", handleA)] {
        for index in 1 ... attempts {
            setScene(otherTab: otherTab)
            results.append(attempt(to: target, label: label, prefix: "\(label) \(index)/\(attempts) "))
        }
    }
    print(order())
    for (label, part) in [("A", results.prefix(attempts)), ("B", results.suffix(attempts))] {
        print("summary \(app.rawValue) → \(label): \(part.filter(\.right).count) of \(attempts) right")
    }
    summarize(results)
}

func awkward(_ name: String, attempts: Int) {
    var results: [Attempt] = []
    for index in 1 ... attempts {
        let prefix = "\(name) \(index)/\(attempts) "
        switch name {
        case "minimized":
            // Minimize the spike window while tab B is selected, so A is a background tab in it.
            _ = osascript([app.focusScript, handleB])
            let minimize = "set miniaturized of window id \(windowB) to true"
            _ = osascript(["-e", "tell application \"\(app.scriptName)\" to \(minimize)"])
            waitFor { !onScreenWindows().contains { $0.number == windowB } }
            _ = osascript(["-e", "tell application \"\(app.other.scriptName)\" to activate"])
            results.append(attempt(to: handleA, label: "A, window minimized", prefix: prefix))
        case "gone":
            let gone = app == .terminal ? "/dev/ttys999" : UUID().uuidString
            setScene(otherTab: handleB)
            let before = currentSignals().line
            let clock = ContinuousClock()
            let start = clock.now
            let (status, message) = osascript([app.focusScript, gone])
            let took = seconds(clock.now - start)
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

// MARK: - Helpers

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

func runScript(_ source: String) -> String {
    osascript(["-e", source]).message
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
    return Int(runScript(source)) ?? 0
}

func label(_ handle: String) -> String {
    handle == handleA ? "A" : handle == handleB ? "B" : handle.isEmpty ? "none" : "other"
}

func waitFor(_ condition: () -> Bool) {
    let clock = ContinuousClock()
    let start = clock.now
    while !condition(), clock.now - start < .seconds(3) {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.02))
    }
}

func seconds(_ duration: Duration) -> Double {
    Double(duration.components.seconds) + Double(duration.components.attoseconds) / 1e18
}

func median(_ values: [Double]) -> Double {
    values.isEmpty ? 0 : values[values.count / 2]
}

func format(_ value: Double) -> String {
    String(format: "%.3fs", value)
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}
