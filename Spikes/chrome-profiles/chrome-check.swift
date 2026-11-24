// Spike helper for card #56. Not part of the app and not built by the check. See README.md.
//   swift chrome-check.swift setup   <scratch>
//   swift chrome-check.swift cold    <scratch> <open|binary> [tries, 1 to 12, default 10]
//   swift chrome-check.swift warm    <scratch> <open|binary> [tries]
//   swift chrome-check.swift forward <scratch> open [tries]
//   swift chrome-check.swift probe   <scratch> open
// Every mode but setup starts its own throwaway Chrome with <scratch>/ud as its user data folder, records the
// browser's process ID, and stops that process with `kill <pid>` before the try ends, so no throwaway Chrome is left
// running between tries. Every launch carries --user-data-dir. Apple events go to that process ID only, never to
// Chrome by name or bundle ID, and never read a window's name or a tab's title or URL. The window server's list is
// read without window names. The output names profiles by their sample names, and windows by their profile.
// Exit status: 0 after a run, 1 when it was refused or stopped, 3 when it was interrupted.
import AppKit
import ScriptingBridge

let bundleID = "com.google.Chrome"
let profiles = [("Acme", "Default"), ("Globex", "Profile 1"), ("Personal", "Profile 2")].map { (name: $0, folder: $1) }
var running: pid_t = 0

func fail(_ message: String) -> Never {
    print("STOP: \(message)")
    stopInstance()
    exit(1)
}

enum Way: String { case open, binary }

let args = Array(CommandLine.arguments.dropFirst())
let mode = args.first ?? ""
guard args.count >= 2, ["setup", "cold", "warm", "forward", "probe"].contains(mode) else {
    fail("usage: see the top of chrome-check.swift")
}

/// The canonical path keeps `/private`, as `pwd -P` in the README does, so `pgrep -f "$S/ud"` finds the instance.
let scratch = (try? URL(fileURLWithPath: args[1]).resourceValues(forKeys: [.canonicalPathKey]).canonicalPath) ?? ""
guard scratch.contains("/dontburn-chrome.") else { fail("\(args[1]) is not a scratch folder from the README's setup") }
let (userData, pidFile) = (scratch + "/ud", scratch + "/pid")
let way: Way = {
    let way = mode == "setup" ? .open : args.count > 2 ? Way(rawValue: args[2]) : nil
    guard let way, way == .open || mode == "cold" || mode == "warm" else { fail("the way is open or binary") }
    return way
}()

let tries = args.count > 3 ? Int(args[3]) ?? 0 : 10
guard (1 ... 12).contains(tries) else { fail("tries: a number from 1 to 12") }

/// One more flag than the card names: without it, a new profile in the EU opens Chrome's search engine choice
/// dialog over its first window.
func flags(_ directory: String) -> [String] {
    ["--user-data-dir=\(userData)", "--profile-directory=\(directory)", "--no-first-run",
     "--no-default-browser-check", "--use-mock-keychain", "--disable-search-engine-choice-screen"]
}

@discardableResult
func run(_ path: String, _ arguments: [String]) -> String {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: path)
    process.arguments = arguments
    let pipe = Pipe()
    process.standardOutput = pipe
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { fail("cannot run \(path)") }
    let data = pipe.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    return String(bytes: data, encoding: .utf8) ?? ""
}

let binary: String = {
    guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else {
        fail("Chrome is not installed")
    }
    return app.appendingPathComponent("Contents/MacOS/Google Chrome").path
}()

/// The throwaway browser's main process: Chrome's binary with the scratch user data folder, and no helper.
func isThrowaway(_ pid: pid_t) -> Bool {
    let line = run("/bin/ps", ["-ww", "-p", "\(pid)", "-o", "command="])
    return line.hasPrefix(binary + " ") && line.contains("--user-data-dir=\(userData) ") && !line.contains("--type=")
}

/// Process IDs whose command line holds the scratch user data folder. No other command line is shown.
func scratchProcesses() -> [pid_t] {
    run("/usr/bin/pgrep", ["-f", userData]).split(separator: "\n").compactMap { pid_t($0) }
}

func stopInstance() {
    guard running != 0 else { return }
    let pid = running
    running = 0
    guard isThrowaway(pid) else { return print("  \(pid) is no longer the throwaway Chrome: nothing sent to it") }
    kill(pid, SIGTERM)
    let gone = waitFor(10) { run("/bin/ps", ["-p", "\(pid)", "-o", "pid="]).isEmpty }
    _ = waitFor(5) { scratchProcesses().isEmpty }
    print("  stopped \(pid): \(gone ? "gone" : "STILL RUNNING"), processes left \(scratchProcesses())")
    try? FileManager.default.removeItem(atPath: pidFile) // the file only helps a manual stop
}

func waitFor(_ seconds: Double, _ probe: () -> Bool) -> Bool {
    let deadline = Date().addingTimeInterval(seconds)
    while !probe() {
        guard Date() < deadline else { return false }
        usleep(100_000)
    }
    return true
}

/// Starts a process with the profile's flags. With `.binary` and no instance running, that process is the browser.
func launch(_ way: Way, _ directory: String) -> Process {
    let process = Process()
    process.executableURL = URL(fileURLWithPath: way == .open ? "/usr/bin/open" : binary)
    process.arguments = (way == .open ? ["-n", "-b", bundleID, "--args"] : []) + flags(directory)
    process.standardOutput = FileHandle.nullDevice
    process.standardError = FileHandle.nullDevice
    do { try process.run() } catch { fail("cannot start \(way.rawValue)") }
    return process
}

/// Waits for a launch that hands its arguments to the running instance, and stops it when it does not end.
func finish(_ process: Process) {
    guard !waitFor(10, { !process.isRunning }) else { return }
    process.terminate()
    fail("the launch for the running instance did not end within 10 s")
}

/// Starts the instance with one profile and waits for its browser process and its first window. Only `cold` starts it
/// as the caller's child: macOS then holds the caller responsible for Chrome's own requests, such as Local Network.
func startInstance(_ directory: String) -> Int {
    guard running == 0, scratchProcesses().isEmpty else { fail("a throwaway Chrome for this folder still runs") }
    let child = mode == "cold" && way == .binary
    let process = launch(child ? .binary : .open, directory)
    let candidate = { child ? process.processIdentifier : scratchProcesses().first(where: isThrowaway) }
    guard waitFor(15, { candidate().map(isThrowaway) == true }), let pid = candidate() else {
        fail("no throwaway browser process within 15 s. Processes with the scratch folder: \(scratchProcesses())")
    }
    running = pid
    try? String(pid).write(toFile: pidFile, atomically: true, encoding: .utf8) // only helps a manual stop
    guard waitFor(15, { !windows(pid).isEmpty }), let first = windows(pid).first else { fail("no window in 15 s") }
    return first.number
}

/// Normal on-screen windows of the process, front to back, from the window server. Never the window's name.
/// On-screen only: Chrome keeps hidden windows of its own, one of them 500 by 500 points.
func windows(_ pid: pid_t) -> [(number: Int, bounds: CGRect)] {
    let list = CGWindowListCopyWindowInfo([.optionOnScreenOnly, .excludeDesktopElements], 0) as? [[String: Any]] ?? []
    return list.compactMap { info in
        guard info[kCGWindowOwnerPID as String] as? pid_t == pid, info[kCGWindowLayer as String] as? Int == 0,
              let number = info[kCGWindowNumber as String] as? Int,
              let raw = info[kCGWindowBounds as String] as? NSDictionary,
              let bounds = CGRect(dictionaryRepresentation: raw),
              bounds.width >= 300, bounds.height >= 200 else { return nil }
        return (number, bounds)
    }
}

func frontPID() -> pid_t {
    let asn = run("/usr/bin/lsappinfo", ["front"]).trimmingCharacters(in: .whitespacesAndNewlines)
    let match = try? Regex(#"pid"? ?= ?(\d+)"#).firstMatch(in: run("/usr/bin/lsappinfo", ["info", "-only", "pid", asn]))
    return pid_t(match?.output[1].substring ?? "") ?? 0
}

/// The app the run comes back to before each try, as a user working elsewhere would be. Never a Chrome.
let home: (pid: pid_t, bundle: String) = {
    let pid = frontPID()
    guard let bundle = NSRunningApplication(processIdentifier: pid)?.bundleIdentifier, bundle != bundleID else {
        fail("bring the terminal you run this from to the front first, not Chrome")
    }
    return (pid, bundle)
}()

func homeInFront() {
    run("/usr/bin/open", ["-b", home.bundle])
    guard waitFor(3, { frontPID() == home.pid }) else { fail("the app to come back to did not come forward in 3 s") }
}

func label(_ pid: pid_t) -> String {
    switch pid {
    case running: "throwaway"
    case home.pid: "home"
    case _ where NSRunningApplication(processIdentifier: pid)?.bundleIdentifier == bundleID: "OWNER'S CHROME"
    default: "other"
    }
}

struct Reading {
    var front: pid_t
    var chromeFront: Int?
    var new: [Int]
    var settled: Double?
}

func read(_ before: Set<Int>) -> Reading {
    Reading(front: frontPID(), chromeFront: windows(running).first?.number,
            new: windows(running).map(\.number).filter { !before.contains($0) })
}

enum Verdict: String {
    case forward = "FORWARD", newFront = "NEW, FRONT", newBehind = "NEW, BEHIND", newMany = "SEVERAL NEW",
         nothing = "NOTHING", discard = "DISCARDED"
}

/// Reads the signals until they settle, for up to 5 s, then once more 2 s after the command for a late window.
func observe(since started: Date, before: Set<Int>, target: Int) -> (Verdict, Reading) {
    var settled: Double?
    _ = waitFor(5) {
        let reading = read(before)
        guard reading.front == running, let front = reading.chromeFront,
              reading.new.isEmpty ? front == target : reading.new.contains(front) else { return false }
        settled = Date().timeIntervalSince(started)
        return true
    }
    usleep(useconds_t(max(0, 2 - Date().timeIntervalSince(started)) * 1_000_000))
    var reading = read(before)
    reading.settled = settled
    if label(reading.front) == "OWNER'S CHROME" {
        fail("the owner's Chrome came to the front. Nothing more is sent")
    }
    let verdict: Verdict = switch (reading.new.count, reading.front == running) {
    case _ where reading.front != running && reading.front != home.pid: .discard
    case (0, true) where reading.chromeFront == target: .forward
    case (0, _): .nothing
    case (1, true) where reading.chromeFront == reading.new[0]: .newFront
    case (1, _): .newBehind
    default: .newMany
    }
    return (verdict, reading)
}

final class Failures: NSObject, SBApplicationDelegate {
    var codes: [Int] = []

    func eventDidFail(_: UnsafePointer<AppleEvent>, withError error: any Error) -> Any? {
        codes.append((error as NSError).code)
        return nil
    }
}

let failures = Failures()

/// Checked before every batch of Apple events: the process ID still belongs to the throwaway instance.
func scripting() -> SBApplication {
    guard isThrowaway(running), let app = SBApplication(processIdentifier: running) else {
        fail("process \(running) is not the throwaway Chrome. No Apple event is sent")
    }
    app.delegate = failures
    return app
}

func chromeWindows(_ app: SBApplication) -> SBElementArray? {
    app.value(forKey: "windows") as? SBElementArray
}

/// One property of every window, front to back, in one Apple event. Only properties that hold no page content.
func property(_ key: String, _ app: SBApplication) -> [Any] {
    precondition(["id", "index", "givenName", "mode", "minimized", "visible", "bounds"].contains(key))
    return chromeWindows(app)?.array(byApplying: NSSelectorFromString(key)) ?? []
}

func permission() -> OSStatus {
    let target = NSAppleEventDescriptor(processIdentifier: running)
    return AEDeterminePermissionToAutomateTarget(target.aeDesc, typeWildCard, typeWildCard, false)
}

/// The event AppleScript's `activate` sends.
func activate() {
    let event = NSAppleEventDescriptor.appleEvent(withEventClass: AEEventClass(kAEMiscStandards),
                                                  eventID: AEEventID(kAEActivate),
                                                  targetDescriptor: NSAppleEventDescriptor(processIdentifier: running),
                                                  returnID: AEReturnID(kAutoGenerateReturnID),
                                                  transactionID: AETransactionID(kAnyTransactionID))
    do { _ = try event.sendEvent(options: [.waitForReply], timeout: 10) } catch {
        failures.codes.append((error as NSError).code)
    }
}

func seconds(_ value: Double?) -> String {
    value.map { String(format: "%.2fs", $0) } ?? "-"
}

/// Starts the instance with the target's profile, then opens one window for each other profile.
/// Returns the windows by profile name, and how many of the set-up's opens gave exactly one new window.
func setScene(target: Int) -> (names: [Int: String], opens: Int) {
    var names = [startInstance(profiles[target].folder): profiles[target].name]
    var opens = 0
    for other in profiles.indices where other != target {
        let before = Set(windows(running).map(\.number))
        finish(launch(way, profiles[other].folder))
        _ = waitFor(5) { windows(running).contains { !before.contains($0.number) } }
        usleep(500_000)
        let new = windows(running).map(\.number).filter { !before.contains($0) }
        opens += new.count == 1 ? 1 : 0
        new.forEach { names[$0] = profiles[other].name }
    }
    return (names, opens)
}

if (CGSessionCopyCurrentDictionary() as? [String: Any])?["CGSSessionScreenIsLocked"] as? Bool == true {
    fail("the screen is locked. Unlock it first")
}

let signalSources = [SIGTERM, SIGINT, SIGHUP].map { number in
    signal(number, SIG_IGN)
    let source = DispatchSource.makeSignalSource(signal: number, queue: .global())
    source.setEventHandler {
        stopInstance()
        exit(3)
    }
    source.resume()
    return source
}

switch mode {
case "setup":
    guard !FileManager.default.fileExists(atPath: userData) else { fail("\(userData) exists already") }
    let cache = Dictionary(uniqueKeysWithValues: profiles.map {
        ($0.folder, ["name": $0.name, "is_using_default_name": false] as [String: Any])
    })
    do {
        try FileManager.default.createDirectory(atPath: userData, withIntermediateDirectories: false)
        try JSONSerialization.data(withJSONObject: ["profile": ["info_cache": cache]])
            .write(to: URL(fileURLWithPath: userData + "/Local State"))
    } catch { fail("cannot write the user data folder") }
    print("user data folder \(userData): " + profiles.map { "\($0.folder) = \($0.name)" }.joined(separator: ", "))

case "probe":
    homeInFront()
    _ = startInstance(profiles[0].folder)
    print("started the throwaway Chrome \(running). Permission before any Apple event, no prompt: \(permission())")
    let app = scripting()
    app.timeout = 120 * 60 // ticks: two minutes for the owner to answer the prompt
    var count = chromeWindows(app)?.count
    if failures.codes.last == -1712 {
        print("the first count timed out (-1712), retrying once")
        failures.codes = []
        count = chromeWindows(app)?.count
    }
    print("count of windows: \(count.map(String.init) ?? "-"), errors \(failures.codes), now \(permission())")
    guard failures.codes.isEmpty else { fail("the first Apple event failed") }
    for other in profiles.dropFirst() {
        finish(launch(.open, other.folder))
        _ = waitFor(5) { windows(running).count == profiles.count }
    }
    for key in ["id", "index", "givenName", "mode", "minimized", "visible", "bounds"] {
        print("windows' \(key): \(property(key, scripting()))") // each batch checks the process ID again
    }
    print("window server: " + windows(running).map { "\($0.number) \($0.bounds)" }.joined(separator: "; "))
    print("errors \(failures.codes)")
    stopInstance()

default:
    var verdicts: [Verdict: Int] = [:]
    var setUpOpens = 0
    var times: [Double] = []
    for index in 0 ..< tries {
        let target = index % profiles.count
        var names: [Int: String] = [:]
        var targetWindow = 0
        var afterIndex = ""
        let started: Date
        if mode == "cold" {
            homeInFront()
            started = Date()
            names[startInstance(profiles[target].folder)] = profiles[target].name
        } else {
            let scene = setScene(target: target)
            names = scene.names
            setUpOpens += scene.opens
            targetWindow = names.first { $0.value == profiles[target].name }?.key ?? 0
            // The target's window opened first, so Chrome's dictionary lists it last, front to back.
            let ids = mode == "forward" ? property("id", scripting()) : []
            guard mode != "forward" || ids.count == profiles.count else { fail("the dictionary lists \(ids.count)") }
            homeInFront()
            guard isThrowaway(running) else { fail("process \(running) is no longer the throwaway Chrome") }
            started = Date()
            if let targetID = ids.last.map({ "\($0)" }) {
                let app = scripting()
                (chromeWindows(app)?.object(withID: targetID) as? SBObject)?.setValue(1, forKey: "index")
                afterIndex = " front-after-index=\(label(frontPID()))"
                activate()
            } else {
                finish(launch(way, profiles[target].folder))
            }
        }
        let command = Date().timeIntervalSince(started)
        let before = mode == "cold" ? [] : Set(names.keys)
        let (verdict, reading) = observe(since: started, before: before, target: targetWindow)
        verdicts[verdict, default: 0] += 1
        times += [reading.settled].compactMap(\.self)
        let front = reading.chromeFront.map { before.contains($0) ? names[$0] ?? "?" : "new" } ?? "none"
        print("\(index + 1)/\(tries) \(profiles[target].name): \(verdict.rawValue) front=\(label(reading.front))"
            + " chrome-front=\(front) new=\(reading.new.count)\(afterIndex) command=\(seconds(command))"
            + " settled=\(seconds(reading.settled))" + (failures.codes.isEmpty ? "" : " errors=\(failures.codes)"))
        failures.codes = []
        stopInstance()
    }
    times.sort()
    let counts = verdicts.sorted { $0.key.rawValue < $1.key.rawValue }.map { "\($0.key.rawValue) \($0.value)" }
    print("\(mode) \(way.rawValue): \(counts.joined(separator: ", ")) of \(tries). "
        + (mode == "cold" ? "" : "Set-up opens with exactly one new window: \(setUpOpens) of \(tries * 2). ")
        + "Settled median \(seconds(times.isEmpty ? nil : times[times.count / 2])), worst \(seconds(times.last))")
}
