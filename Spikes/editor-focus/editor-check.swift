// Spike helper for card #7. Not part of the app and not built by the check. See README.md.
//   swift editor-check.swift try     <scratch> <vscode|cursor> <open|cli|app> <target> [expected window]
//   swift editor-check.swift measure <scratch> <vscode|cursor> <open|cli|app> [attempts, 1 to 20, default 10]
//   swift editor-check.swift session <scratch> [open|cli|app]
//   swift editor-check.swift windows <scratch>
// <target> is a name from `target(_:)`. A window that appears during an attempt is noted in <scratch>/windows
// under that name, by its number. Window names are never read, and no path outside <scratch> is shown.
// Exit status: 0 when done, 1 when an expected window was named and the verdict is not RIGHT, or when
// `measure` met a new window and stopped, 2 when the arguments or the starting state were refused.
import AppKit

enum Editor: String, CaseIterable {
    case vscode, cursor

    var bundleID: String {
        self == .vscode ? "com.microsoft.VSCode" : "com.todesktop.230313mzl4w4u92"
    }

    var other: Editor {
        self == .vscode ? .cursor : .vscode
    }

    /// The shell command inside the app bundle, so nothing depends on `code` or `cursor` being on PATH.
    var cli: String {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
            fail("\(rawValue) is not installed")
        }
        return app.path + "/Contents/Resources/app/bin/" + (self == .vscode ? "code" : "cursor")
    }
}

typealias Target = (name: String, argument: String)

struct Timing {
    var command: Double
    var agree: Double?
    var newWindows: Int
}

struct Noted {
    var editor: Editor
    var name: String
    var number: Int
}

struct Window {
    var pid: pid_t
    var number: Int
    var bounds: CGRect
}

struct Signals {
    var front = "other"
    var editorFront = 0
    var topOverTarget = 0
    var newWindows: [Int] = []

    func right(_ editor: Editor, _ target: Int) -> Bool {
        front == editor.rawValue && editorFront == target && topOverTarget == target && newWindows.isEmpty
    }

    func line(_ editor: Editor, _ target: Int) -> String {
        let server = target == 0 ? "" : topOverTarget == 0 ? " server=off screen"
            : " server=\(topOverTarget == target ? "on top" : "covered")"
        return "front=\(front) \(editor.rawValue)-front=\(label(editor, editorFront))\(server) new=\(newWindows.count)"
    }
}

let args = Array(CommandLine.arguments.dropFirst())
let scratch: String = {
    let needed = ["try": 5, "measure": 4, "session": 2, "windows": 2][args.first ?? ""] ?? 99
    guard args.count >= needed else { fail("usage: see the top of editor-check.swift") }
    let path = URL(fileURLWithPath: args[1]).resolvingSymlinksInPath().path
    guard path.contains("/dontburn-editor."), FileManager.default.fileExists(atPath: path + "/acme-web") else {
        fail("\(args[1]) is not a scratch folder from the README's setup")
    }
    return path
}()

/// Refused before anything is looked at or sent: every attempt can open a window.
let attempts = args[0] == "measure" && args.count > 4 ? Int(args[4]) ?? 0 : 10
guard (1 ... 20).contains(attempts) else { fail("attempts per window: a number from 1 to 20") }

if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true {
    fail("The screen is locked, so the login window is the frontmost app. Unlock it first.")
}

/// The spike never starts an editor: `open -b` would launch one that is not running.
let pids = Dictionary(uniqueKeysWithValues: Editor.allCases.map { editor in
    let app = NSRunningApplication.runningApplications(withBundleIdentifier: editor.bundleID).first
    return (editor, app?.processIdentifier ?? 0)
})
for editor in Editor.allCases where pids[editor] == 0 {
    fail("\(editor.rawValue) is not running. Start it by hand first.")
}

switch args[0] {
case "try":
    let (editor, route, target) = (editor(args[2]), route(args[3]), target(args[4]))
    let scene = setScene(editor, awayFrom: target.name == "B" ? "A" : "B")
    let result = attempt(editor, route, target, expected: args.count > 5 ? args[5] : nil, prefix: scene)
    if args.count > 5, result.agree == nil { exit(1) }
case "measure":
    measure(editor(args[2]), route(args[3]), attempts: attempts)
case "session":
    session(route: args.count > 2 ? route(args[2]) : "open")
case "windows":
    for noted in recorded() {
        let open = editorWindows(noted.editor, onScreenOnly: false).contains { $0.number == noted.number }
        print("\(noted.editor.rawValue) \(noted.name): \(open ? "still open" : "closed")")
    }
default:
    fail("usage: see the top of editor-check.swift")
}

/// What a focus command is given, by name. The folders sit in the scratch folder.
func target(_ name: String) -> Target {
    let folders = ["A": "acme-web", "B": "globex-app", "api": "acme-web/packages/api", "web": "acme-web/packages/web",
                   "container-host": "acme-container"]
    if let folder = folders[name] {
        return (name, scratch + "/" + folder)
    }
    switch name {
    case "B-var":
        // The same folder as B, spelled through the /var symlink, as a shell's $PWD can spell it.
        guard scratch.hasPrefix("/private/var/") else { fail("the scratch folder is not under /private/var") }
        return (name, String(scratch.dropFirst("/private".count)) + "/globex-app")
    case "container":
        // The URI of the window Dev Containers opens: the host folder in hex, then the folder inside.
        let hex = Data((scratch + "/acme-container").utf8).map { String(format: "%02x", $0) }.joined()
        return (name, "vscode-remote://dev-container+\(hex)/workspaces/acme-container")
    case "container-path":
        return (name, "/workspaces/acme-container")
    default:
        fail("targets: A, B, api, web, B-var, container, container-host, container-path")
    }
}

/// The focus commands under test: `open -b <bundle id> <folder>`, the editor's bundled CLI with the
/// folder, and `open -b <bundle id>` alone, which only activates the editor.
func focusCommand(_ editor: Editor, _ route: String, _ argument: String) -> (tool: String, arguments: [String]) {
    let isURI = argument.contains("://")
    if route == "app" {
        return ("/usr/bin/open", ["-b", editor.bundleID])
    }
    if route == "open" {
        guard !isURI else { fail("open -b is given folders here, not URIs") }
        return ("/usr/bin/open", ["-b", editor.bundleID, argument])
    }
    return (editor.cli, isURI ? ["--folder-uri", argument] : [argument])
}

func editor(_ name: String) -> Editor {
    guard let editor = Editor(rawValue: name) else { fail("the editors are vscode and cursor") }
    return editor
}

func route(_ name: String) -> String {
    guard ["open", "cli", "app"].contains(name) else { fail("the routes are open, cli and app") }
    return name
}

/// Normal windows (layer 0) that can be seen, front to back. Without Screen Recording permission the
/// list has no window names, and none are read here.
func windows(onScreenOnly: Bool) -> [Window] {
    let options: CGWindowListOption = [onScreenOnly ? .optionOnScreenOnly : .optionAll, .excludeDesktopElements]
    let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] ?? []
    return list.compactMap { info in
        guard info[kCGWindowLayer as String] as? Int == 0,
              (info[kCGWindowAlpha as String] as? Double ?? 0) > 0,
              let pid = info[kCGWindowOwnerPID as String] as? pid_t,
              let number = info[kCGWindowNumber as String] as? Int,
              let bounds = (info[kCGWindowBounds as String] as? NSDictionary)
                  .flatMap({ CGRect(dictionaryRepresentation: $0) })
        else { return nil }
        return Window(pid: pid, number: number, bounds: bounds)
    }
}

/// The editor's real windows, without Electron's title-bar strips and small helper windows. With
/// `onScreenOnly` false the list includes minimized windows and windows on other Spaces.
func editorWindows(_ editor: Editor, onScreenOnly: Bool) -> [Window] {
    windows(onScreenOnly: onScreenOnly).filter {
        $0.pid == pids[editor] && $0.bounds.width >= 300 && $0.bounds.height >= 200
    }
}

func frontApp() -> String {
    // From LaunchServices, not NSWorkspace: a command-line process sees NSWorkspace's
    // frontmost app change only while its run loop delivers the notifications.
    let front = run("/usr/bin/lsappinfo", ["info", "-only", "bundleid", run("/usr/bin/lsappinfo", ["front"]).message])
    let bundleLine = front.message.split(separator: "\n")
        .first { $0.contains("bundleID=") || $0.contains("CFBundleIdentifier") }
    let bundleID = bundleLine?.split(separator: "\"").last.map(String.init)
    let editor = Editor.allCases.first { $0.bundleID == bundleID }
    return bundleID == "com.apple.Terminal" ? "terminal" : editor?.rawValue ?? "other"
}

func signals(_ editor: Editor, target: Int, before: Set<Int>) -> Signals {
    var signals = Signals()
    signals.front = frontApp()
    let onScreen = windows(onScreenOnly: true)
    signals.editorFront = editorWindows(editor, onScreenOnly: true).first?.number ?? 0
    // The topmost window over the target's spot. Not simply the topmost window: with several
    // displays, a window elsewhere can be higher in the list without covering it.
    if let spot = onScreen.first(where: { $0.number == target }) {
        signals.topOverTarget = onScreen.first { $0.bounds.intersects(spot.bounds) }?.number ?? 0
    }
    signals.newWindows = editorWindows(editor, onScreenOnly: false).map(\.number).filter { !before.contains($0) }
    return signals
}

func recorded() -> [Noted] {
    let text = (try? String(contentsOfFile: scratch + "/windows", encoding: .utf8)) ?? ""
    return text.split(separator: "\n").compactMap { line in
        let parts = line.split(separator: " ").map(String.init)
        guard parts.count == 3, let editor = Editor(rawValue: parts[0]), let number = Int(parts[2]) else { return nil }
        return Noted(editor: editor, name: parts[1], number: number)
    }
}

func note(_ editor: Editor, _ name: String, _ number: Int) {
    let text = recorded().map { "\($0.editor.rawValue) \($0.name) \($0.number)\n" }.joined()
    do {
        try (text + "\(editor.rawValue) \(name) \(number)\n").write(toFile: scratch + "/windows", atomically: true,
                                                                    encoding: .utf8)
    } catch { fail("cannot note window \(number): \(error)") }
}

func spikeWindow(_ editor: Editor, _ name: String) -> Int {
    let open = Set(editorWindows(editor, onScreenOnly: false).map(\.number))
    return recorded().last { $0.editor == editor && $0.name == name && open.contains($0.number) }?.number ?? 0
}

func label(_ editor: Editor, _ number: Int) -> String {
    number == 0 ? "none" : recorded().last { $0.editor == editor && $0.number == number }?.name ?? "other"
}

/// Makes the other spike window the editor's last active one, then puts another app in front: the
/// other editor's window on the same folder when there is one, else Terminal. That is how the Focus
/// button is used: from the menu bar, while the user works elsewhere. Stops when the state is not reached.
func setScene(_ editor: Editor, awayFrom otherName: String, sameFolder name: String? = nil) -> String {
    let other = spikeWindow(editor, otherName)
    if other != 0 {
        _ = run("/usr/bin/open", ["-b", editor.bundleID, target(otherName).argument])
        guard waitFor(seconds: 3, { editorWindows(editor, onScreenOnly: true).first?.number == other }) else {
            fail("\(editor.rawValue) did not bring its \(otherName) window forward for the starting state")
        }
    }
    let twin = name.map { spikeWindow(editor.other, $0) } ?? 0
    if let name, twin != 0 {
        _ = run("/usr/bin/open", ["-b", editor.other.bundleID, target(name).argument])
    } else {
        _ = run("/usr/bin/osascript", ["-e", "tell application \"Terminal\" to activate"])
    }
    let away = twin != 0 ? editor.other.rawValue : "terminal"
    let ready = waitFor(seconds: 3) {
        frontApp() == away && (twin == 0 || editorWindows(editor.other, onScreenOnly: true).first?.number == twin)
    }
    guard ready else { fail("The starting state was not reached: \(frontApp()) is in front, not \(away)") }
    let last = label(editor, editorWindows(editor, onScreenOnly: true).first?.number ?? 0)
    return "from=\(away)\(twin != 0 ? " on the same folder" : ""),\(editor.rawValue) last on \(last) "
}

/// Runs a focus command once, reads the signals until they agree or 6 seconds pass, and notes any
/// new window. Returns the command's time, and the time until the signals agreed when they did.
@discardableResult
func attempt(_ editor: Editor, _ route: String, _ target: Target, expected: String?, prefix: String) -> Timing {
    let number = expected.map { spikeWindow(editor, $0) } ?? 0
    guard expected == nil || number != 0 else { fail("\(editor.rawValue) has no spike window \(expected ?? "")") }
    let before = Set(editorWindows(editor, onScreenOnly: false).map(\.number))
    let command = focusCommand(editor, route, target.argument)
    let start = Date()
    let result = run(command.tool, command.arguments)
    let took = -start.timeIntervalSinceNow
    var now = signals(editor, target: number, before: before)
    var readings = 1
    while !(number != 0 && now.right(editor, number)), -start.timeIntervalSinceNow < 6 {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
        now = signals(editor, target: number, before: before)
        readings += 1
    }
    let agree = -start.timeIntervalSinceNow
    // A second window can appear after the right one came forward. Look once more at 2 seconds.
    if agree < 2 {
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 2 - agree))
        now.newWindows = signals(editor, target: number, before: before).newWindows
    }
    for window in now.newWindows {
        note(editor, target.name, window)
    }
    let right = number != 0 && now.right(editor, number)
    let verdict = !now.newWindows.isEmpty ? "NEW WINDOW" : number == 0 ? "no new window" : right ? "RIGHT" : "WRONG"
    print(prefix + "\(editor.rawValue) \(route) → \(target.name): \(verdict) exit=\(result.status)"
        + " command=\(format(took)) agree=\(right ? format(agree) : "never") readings=\(readings)"
        + " \(now.line(editor, number))" + (result.message.isEmpty ? "" : " message=\"\(result.message)\""))
    return Timing(command: took, agree: right ? agree : nil, newWindows: now.newWindows.count)
}

/// Attempts to A and to B, each with the other as the editor's last active window and the other editor
/// in front on the same folder: two windows of one editor, and one folder open in both editors.
func measure(_ editor: Editor, _ route: String, attempts: Int) {
    guard spikeWindow(editor, "A") != 0, spikeWindow(editor, "B") != 0 else {
        fail("open the spike windows A and B in \(editor.rawValue) first")
    }
    var results: [Timing] = []
    for (name, other) in [("A", "B"), ("B", "A")] {
        for index in 1 ... attempts {
            let scene = setScene(editor, awayFrom: other, sameFolder: name)
            let result = attempt(editor, route, target(name), expected: name,
                                 prefix: "\(name) \(index)/\(attempts) \(scene)")
            // An unwanted window is worse than no focus, so the run never goes on to open another.
            guard result.newWindows == 0 else { fail("measure stopped: a new window at \(name) \(index)", status: 1) }
            results.append(result)
        }
    }
    for (name, part) in [("A", results.prefix(attempts)), ("B", results.suffix(attempts))] {
        print("summary \(editor.rawValue) \(route) → \(name): \(part.count { $0.agree != nil }) of \(attempts) right")
    }
    let command = results.map(\.command).sorted()
    let agree = results.compactMap(\.agree).sorted()
    print("timing: command median \(format(median(command))), worst \(format(command.last ?? 0));"
        + " signals agree median \(format(median(agree))), worst \(format(agree.last ?? 0))")
}

/// The main case end to end: the last SessionStart the claude-hook spike logged, the editor its bundle
/// id names and its cwd, then the focus command for that editor and folder.
func session(route: String) {
    let text = (try? String(contentsOfFile: scratch + "/events.jsonl", encoding: .utf8)) ?? ""
    let starts = text.split(separator: "\n").compactMap { line in
        (try? JSONSerialization.jsonObject(with: Data(line.utf8))) as? [String: Any]
    }.filter { $0["event"] as? String == "SessionStart" }
    guard let start = starts.last, let cwd = start["cwd"] as? String else {
        fail("no SessionStart in <scratch>/events.jsonl yet")
    }
    let env = start["env"] as? [String: String] ?? [:]
    guard let editor = Editor.allCases.first(where: { $0.bundleID == env["__CFBundleIdentifier"] }) else {
        fail("the session is not in VS Code or Cursor: TERM_PROGRAM=\(env["TERM_PROGRAM"] ?? "none")")
    }
    let name = ["A", "B", "api", "web"].first { target($0).argument == cwd }
    print("session: editor=\(editor.rawValue) from __CFBundleIdentifier, TERM_PROGRAM=\(env["TERM_PROGRAM"] ?? "none"),"
        + " cwd=\(scratchName(cwd))")
    let expected = name.flatMap { spikeWindow(editor, $0) != 0 ? $0 : nil }
    let scene = setScene(editor, awayFrom: name == "B" ? "A" : "B")
    let result = attempt(editor, route, (name ?? "cwd", cwd), expected: expected, prefix: scene)
    if expected != nil, result.agree == nil { exit(1) }
}

/// A path as its place in the scratch folder, so no other path reaches the output.
func scratchName(_ path: String) -> String {
    for prefix in [scratch, String(scratch.dropFirst("/private".count))] where path.hasPrefix(prefix + "/") {
        return String(path.dropFirst(prefix.count + 1))
    }
    return path == "/workspaces/acme-container" ? path : "a folder outside the scratch folder"
}

func run(_ tool: String, _ arguments: [String]) -> (status: Int32, message: String) {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: tool)
    process.arguments = arguments
    // A file, not a pipe: the editor CLI starts a detached process that could hold a pipe open.
    let outputPath = scratch + "/.last-output"
    FileManager.default.createFile(atPath: outputPath, contents: nil)
    guard let output = FileHandle(forWritingAtPath: outputPath) else { fail("cannot write \(outputPath)") }
    process.standardOutput = output
    process.standardError = output
    do { try process.run() } catch { fail("\(tool) did not start: \(error)") }
    process.waitUntilExit()
    output.closeFile()
    let text = (try? String(contentsOfFile: outputPath, encoding: .utf8)) ?? ""
    return (process.terminationStatus, text.replacingOccurrences(of: scratch, with: "<scratch>")
        .trimmingCharacters(in: .whitespacesAndNewlines))
}

@discardableResult
func waitFor(seconds limit: Double, _ condition: () -> Bool) -> Bool {
    let start = Date()
    while !condition() {
        guard -start.timeIntervalSinceNow < limit else { return false }
        RunLoop.current.run(until: Date(timeIntervalSinceNow: 0.05))
    }
    return true
}

func median(_ values: [Double]) -> Double {
    guard !values.isEmpty else { return 0 }
    let middle = values.count / 2
    return values.count.isMultiple(of: 2) ? (values[middle - 1] + values[middle]) / 2 : values[middle]
}

func format(_ value: Double) -> String {
    String(format: "%.3fs", value)
}

func fail(_ message: String, status: Int32 = 2) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(status)
}
