# Spike: a Chrome profile for each workspace, and its window brought forward

Card #56. Throwaway code that answers four questions about Google Chrome on macOS:

1. Can the app list Chrome's profiles with the name the user gave each, without reading anything else in Chrome's folder?
2. Can it bring an existing window of one profile to the front? If not, can it open a new window in that profile?
3. Which macOS permission does each way need?
4. What can it know about a profile's windows, such as how many are open, and at what cost to privacy?

It is not part of the app, not in `project.yml` and not built by the check. The findings go to `docs/spikes/`.

| File | What it is |
|---|---|
| `profile-names.swift` | Reads a `Local State` file and prints the number of profiles and their directories. With `--names` it prints each profile's name too, and it refuses `--names` for a file inside Chrome's own folder. It decodes `profile.info_cache.<directory>.name` and nothing else |
| `chrome-check.swift` | Makes the throwaway user data folder, then runs each way against a throwaway Chrome it starts and stops itself, and counts the hits. Run it with `swift`, nothing to build |

**Tested on** macOS 27.2.1 and Google Chrome 157.0.8103.79, from scripts started in Terminal, on 2026-11-23. The Mac's interface is not in English, so every prompt below is given in English from the system's own string table.

## In short

| Part | Answer | How sure |
|---|---|---|
| 1. List the profiles with their names | **Only with the "App Data" permission for Google Chrome.** `Local State` holds every profile's name under `profile.info_cache.<directory>.name`, and decoding only that key works on a copy outside Chrome's folder. But macOS 27.2 protects Chrome's own folder as another app's data: the read of the owner's real file from Terminal was denied, with no prompt | Measured: the throwaway file, and the denied read of the owner's file |
| 2a. Bring an existing window of a profile forward | **Only for a window whose id the app already knows**, with Apple events: `set index of window id <id> to 1`, then `activate`. 10 of 10. Nothing tells which profile a window the user opened belongs to, so the user's own windows cannot be found | Measured on the throwaway. That no property tells the profile: measured, from the dictionary |
| 2b. Open a new window in a profile | **Yes**, with `open -n -b com.google.Chrome --args --profile-directory=<directory>`. Always exactly one new window, in front, whether a window of that profile is open or not, and whether the instance runs or not: 10 of 10 not running, 10 of 10 running, and 20 of 20 opens in the set-ups. Chrome's binary gave the same | Measured on the throwaway, and once on the owner's real Chrome: one new window, in front, in 0.67 s. Which profile, only he can see |
| 3. Permissions | Reading the real `Local State`: "App Data" for Google Chrome (`kTCCServiceSystemPolicyAppDataDetailed`). `open -n`: none. Apple events: Automation. Calling Chrome's binary directly: none for the call, but macOS then holds the caller responsible for Chrome's own requests, and Terminal got a Local Network prompt | Measured, except the Automation and App Data prompts themselves, which did not show |
| 4. What it can know about a profile's windows | **Nothing per profile.** With Automation: how many Chrome windows there are in all, their ids, order, bounds, and whether minimized or incognito. Without any permission, the window server gives the same count and order for Chrome's process | Measured |

## The ways, written before anything ran

Each way is tried first against a throwaway Chrome instance: Chrome started with its own user data folder in `$TMPDIR`, holding three throwaway profiles named Acme, Globex and Personal. A second Chrome with its own user data folder is a separate process with its own single instance, so the owner's Chrome and its profiles are not touched. Only the last stage, after the owner's yes, touches his real Chrome.

| # | Way | What it needs | What it might answer |
|---|---|---|---|
| 1 | Read Chrome's `Local State` file, a JSON file at the top of the user data folder, and take only `profile.info_cache.<directory>.name` | One file read in Chrome's folder. For the owner's real file, his yes. No permission prompt expected: Chrome is not sandboxed and its folder is not one macOS protects | Part 1: every profile's name and its directory (`Default`, `Profile 1`, …), without starting Chrome. Nothing about windows. The file's `info_cache` also holds account emails and Google account names, so the code decodes the one key and nothing else |
| 2 | `open -n -b com.google.Chrome --args --user-data-dir=<folder> --profile-directory=<directory>` | Starts a process through LaunchServices. No permission expected. When an instance for that user data folder already runs, the new process hands its arguments to it and exits | Part 2: whether it brings an existing window of the profile forward or opens a new one, with the instance running and not running, and whether the window comes to the front |
| 3 | The binary inside the app bundle, `"/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"`, with the same arguments | Starts a process as a child of the caller, without LaunchServices. No permission expected, though macOS may hold the caller responsible for Chrome's own requests while Chrome is its child | The same as 2, and whether a window comes forward without the activation LaunchServices grants |
| 4 | `open -b com.google.Chrome --args …` without `-n` | Nothing new | **Not tried, on purpose.** While any Chrome runs, LaunchServices activates the running instance and drops the arguments. With the owner's Chrome running, that instance may be his |
| 5 | Chrome's AppleScript dictionary, read statically: `sdef "/Applications/Google Chrome.app"` | Reads the app bundle. No Apple event, no prompt | Which classes and properties exist for windows, and whether anything in the dictionary names a profile. Done before any live Apple event |
| 6 | Live Apple events to the throwaway instance, addressed by its process ID with Scripting Bridge (`SBApplication(processIdentifier:)`): count the windows, read window `id`, `index`, `given name`, `mode`, `minimized`, `visible` and `bounds`, set a window's `index` to 1, and `activate` | Automation: macOS asks once whether the sending app (the terminal the spike runs in) may control Google Chrome. The answer is stored per sending app and per target bundle ID, so it covers the owner's Chrome as well, which has the same bundle ID | Part 2: whether a window can be brought forward by its `id`, and whether any property tells one profile's window from another's. Part 4: how many windows are open. Never a window's `name`, a tab's `title` or `URL`, and never `execute javascript` |
| 7 | The window server's list, `CGWindowListCopyWindowInfo`, filtered to the throwaway process ID, without `kCGWindowName` | Nothing. The name would need Screen Recording, which is ruled out | Part 4: how many windows the process has and which is in front. Not which profile a window belongs to: every profile's windows belong to one process |
| 8 | `NSWorkspace.openApplication(at:configuration:)` with `createsNewApplicationInstance` and `arguments` | The same as 2 | Not tried separately: it is the API behind `open -n`, so it should behave as way 2. Reasoned |

Ideas set aside before anything ran, each with its reason:

- **Each profile's own `Preferences` file** holds the profile name too, but reading it means reading inside a profile folder. Way 1 reads one file at the top of the user data folder instead.
- **Other keys of `Local State`**, such as the last used profile or the profiles open at the last exit. They would tell which profiles had windows, but the card allows only the names from this file.
- **Chrome's Profiles menu**, which lists the profiles and brings a profile's window forward, is reachable only through Accessibility, which the spec rules out.
- **Window titles.** Chrome may show the profile name in a window's title, but reading a window's name is ruled out, and the window server shows it only with Screen Recording.
- **Remote debugging** (`--remote-debugging-port`) tells each page's browser context apart, which maps to a profile. Chrome must be started with it, recent Chrome refuses it on the default user data folder, and its target list carries every page's URL and title.
- **A companion Chrome extension** in every profile, talking to the app through native messaging, could list and focus that profile's windows. It needs an extension installed in each profile and a manifest written into Chrome's folder, which is changing another tool's settings. Not tried. Its cost goes into the note.
- **`--profile-email`** picks a profile by its account email. The app would have to know the email.

### What counts as a hit

- **Bringing forward:** the intended profile's existing window is Chrome's front window, the throwaway instance is the frontmost app, and no new window appeared.
- **Opening:** exactly one new window appeared, in the intended profile. Whether it also came to the front is recorded on its own.

### The case "Chrome is not running"

The owner's Chrome is never quit, so this is measured as "the throwaway instance is not running": each user data folder has its own single instance. What it means for the real case, where no Chrome runs at all, is reasoned.

## Before a run

- **Focus will jump.** Every try brings a throwaway Chrome window to the front and then your terminal back. Keep hands off the keyboard and the mouse while a run goes: a throwaway window in front takes your typing, and a link clicked in another app may open in the throwaway Chrome. A run of ten tries takes one to two minutes.
- **Start it from a terminal that is in front.** `chrome-check.swift` notes the frontmost app when it starts, refuses to start when that is a Chrome, and brings that app back with `open -b <its bundle id>` before each try. A try ends `DISCARDED` when, at its last reading, the frontmost app is neither the throwaway Chrome nor that app.
- **Unlock the screen, and keep it unlocked.** The helper refuses to run while it is locked.
- **Your own Chrome may keep running.** Every launch carries `--user-data-dir=<scratch>/ud`, so it reaches only the throwaway instance. The helper finds the throwaway browser by its command line, never by name, stops it with `kill <pid>` at the end of every try, and checks with `ps -p <pid>` that it is gone and that no process with the scratch folder is left. If a run is interrupted, `<scratch>/pid` holds the process ID to stop by hand. Never `pkill`, `killall`, or quitting Chrome by name.
- **Apple events** go only to the throwaway process ID, through Scripting Bridge (`SBApplication(processIdentifier:)`) or an `NSAppleEventDescriptor(processIdentifier:)` target. They read only a window's `id`, `index`, `given name`, `mode`, `minimized`, `visible` and `bounds`, and the helper checks before each batch that the process ID still belongs to the throwaway instance. Never `tell application "Google Chrome"`: both instances share the bundle ID.
- **Never `cold <scratch> binary` without a reason.** Chrome started as a child of your terminal makes macOS hold the terminal responsible for Chrome's own requests, and here that showed a Local Network prompt for Terminal (see "Permission prompts"). Every other mode starts the throwaway Chrome through LaunchServices.
- **Flags.** Every launch also carries `--no-first-run --no-default-browser-check --use-mock-keychain --disable-search-engine-choice-screen`. The last one is not on the card: without it, a new profile in the EU opens Chrome's search engine choice dialog over its first window.

## Set up

From the repository root:

```sh
S=$(cd "$(mktemp -d -t dontburn-chrome)" && pwd -P)
H=Spikes/chrome-profiles/chrome-check.swift
swift $H setup "$S"
swift Spikes/chrome-profiles/profile-names.swift "$S/ud/Local State" --names
```

`setup` writes `$S/ud/Local State` with three profiles before Chrome ever runs: `Default` = Acme, `Profile 1` = Globex and `Profile 2` = Personal, each with `is_using_default_name: false`. Chrome creates each profile's folder on the first launch into it and keeps the names. The second line must print `3 profiles, 3 with a name` and the three names.

## How a try is counted

After each command the helper reads three signals every 0.1 s, for up to 5 s, until they settle, and once more 2 s after the command, to catch a late window:

1. **The frontmost app**, from LaunchServices (`lsappinfo front`), by process ID: the throwaway Chrome, the app the run came from, the owner's Chrome, or another app.
2. **Chrome's front window**: the first on-screen normal window (layer 0, at least 300 by 200 points) of the throwaway process in the window server's front-to-back list.
3. **New windows**: on-screen normal windows of the throwaway process that were not there before the command. Only on-screen windows count: Chrome keeps hidden windows of its own, one of them 500 by 500 points.

Window names are never read. The verdicts:

| Verdict | Meaning | Counts as a hit for |
|---|---|---|
| `FORWARD` | The target's existing window is Chrome's front window, Chrome is the frontmost app, and no new window appeared | bringing forward |
| `NEW, FRONT` | Exactly one new window appeared, and it is in front | opening |
| `NEW, BEHIND` | Exactly one new window appeared, but Chrome or that window is not in front | opening, not in front |
| `SEVERAL NEW`, `NOTHING` | More than one new window, or no new window and the target not in front | nothing |
| `DISCARDED` | Another app was in front at the last reading: most likely the user, or a dialog | not counted |

Which profile a new window belongs to is known by construction only: the window that appears after a launch with `--profile-directory=Profile 1` is taken as Globex's. Nothing the spike may read tells it. The profile's name shows at the top right of each throwaway window, so you can check it by eye while a run goes.

## Single steps

Each command is one run of 1 to 12 tries, 10 by default, given as the last argument. The tries go through Acme, Globex and Personal in turn. Each try starts the throwaway Chrome and stops it again.

| Run | Command | What a try does | Needs |
|---|---|---|---|
| Not running, `open` | `swift $H cold "$S" open` | Your terminal in front, the instance not running. Starts it with `open -n -b com.google.Chrome --args <flags> --profile-directory=<target>` | nothing |
| Not running, binary | `swift $H cold "$S" binary` | The same with Chrome's binary started as a child of the helper | nothing, but see "Before a run" |
| Running, `open` | `swift $H warm "$S" open` | Starts the instance with the target's profile, opens a window for each of the two other profiles the same way, brings your terminal to the front, then sends the target's command again | nothing |
| Running, binary | `swift $H warm "$S" binary` | The same, with the instance started through `open -n` and every open by the binary | nothing |
| The first Apple event | `swift $H probe "$S" open` | Asks whether the terminal may send Apple events to Chrome without a prompt, then counts the windows: the one event that may show the Automation prompt, with two minutes for an answer and one retry on −1712. Then opens two more windows and reads each allowed property of all three | Automation |
| Bring a known window forward | `swift $H forward "$S" open` | As `warm open`, then reads the window ids front to back. The target's window opened first, so it is the last. Brings your terminal to the front, then sends `set index of window id <id> to 1` and `activate` (`misc/actv`, the event AppleScript's `activate` sends) to the process ID | Automation |

Chrome's dictionary, without any Apple event: `sdef "/Applications/Google Chrome.app"`.

## Results

Measured on 2026-11-23, macOS 27.2.1, Chrome 157.0.8103.79, sent from Terminal. 54 throwaway instances were started and 136 throwaway windows opened. Every one was closed by stopping its instance with `kill <pid>`, and every stop was checked: the process gone and no process with the scratch folder left.

| Run | Tries | Result | Command | Settled |
|---|---|---|---|---|
| Not running, `open` | 10 | `NEW, FRONT` 10 of 10: one window, in the intended profile, in front | until the first window: 0.90 to 0.96 s | median 1.12 s, worst 1.14 s |
| Not running, binary | 10 | `NEW, FRONT` 9 of 9 counted. Try 1 `DISCARDED`: its window was in front at 0.75 s, then the Local Network prompt for Terminal came to the front | until the first window: 0.53 to 0.58 s | median 0.70 s, worst 0.75 s, the discarded try included |
| Running, `open`, a window of the profile already open | 10 | `NEW, FRONT` 10 of 10. `FORWARD` 0 of 10: the existing window was never brought forward. The set-ups' opens: 20 of 20 exactly one new window | `open` returns in 0.11 s | median 0.58 s, worst 0.59 s |
| Running, binary, a window of the profile already open | 10 | `NEW, FRONT` 10 of 10, `FORWARD` 0 of 10. Set-ups: 20 of 20 | the handing-over process ends in 0.21 to 0.22 s | median 0.40 s, worst 0.41 s |
| Bring a known window forward by Apple events | 10 | `FORWARD` 10 of 10, no new window. Right after `set index … to 1` and before `activate`, the terminal was still the frontmost app every time: setting the index does not bring Chrome forward. Set-ups: 20 of 20 | both events: 0.26 to 0.29 s | median 0.46 s, worst 0.46 s |
| First Apple event | 1 | The permission check returned 0 before any event: Terminal already held Automation for Google Chrome, so no prompt showed. Counting the windows answered 1 | | |
| A profile directory that does not exist (`Profile 9`), not running, `open` | 1 | Chrome **created a new profile**: a `Profile 9` folder and an `info_cache` entry with Chrome's default name ("Your Chrome", in the system's language), and opened one window in it | | |

"Command" is the time the command took. "Settled" runs from the command to the first reading at which the signals agreed.

### Part 1: the profile names

**Measured on the throwaway profiles.** `profile-names.swift` printed `3 profiles, 3 with a name` and the three names before Chrome ever ran, and again after 54 starts, when Chrome had rewritten the file around it (206 bytes before the first start, 5,766 after the last). The fourth profile, made by the missing-directory try, showed up the same way.

- It decodes a `Decodable` type that holds only `profile.info_cache[<directory>].name`. `JSONDecoder` skips every other key without keeping it. Without `--names` it prints only the number of profiles and their directory keys. An error prints only the error's type.
- No prompt and no permission for the throwaway file in `$TMPDIR`.
- **The owner's real file is protected.** Run once from Terminal with his yes, the read of `~/Library/Application Support/Google/Chrome/Local State` failed and printed nothing but the error. The system log shows why: `sandboxd` checked `kTCCServiceSystemPolicyAppDataDetailed` for `com.google.Chrome`, with Terminal as the responsible app, and TCC denied it 12 ms later, so no prompt was on screen. No notification for it shows in the log. The file's size could be read, its content could not. Measured.
- So macOS 27.2 treats Chrome's folder as Chrome's private data, as the card's way 1 did not expect. For the app, the system's string table has this prompt: "Allow “<app>” to access your “Google Chrome” data?" with "This will allow the app to access your data associated with “Google Chrome” on this Mac." When access is blocked, macOS may post "Data Access Blocked": "“<app>” tried to access your data from other apps and was blocked. You can manage this at any time in Files & Folders settings." Whether a third-party app such as this one gets that prompt, where Terminal got none, was not tried, and is for the feature card to find out: Terminal is one of Apple's own apps, and `tccd` logged that it does not prompt for those in another request. Reasoned, not tried.
- `Local State` is not a documented interface, and only Chrome 157 was tried. A later Chrome may move the key, and the reader then finds no profiles. Chrome Beta, Canary and Chromium keep their own folders next to Chrome's. Reasoned.

### Part 2: bringing a window forward, or opening one

**`--profile-directory` never brings an existing window forward.** With the instance running, it opened exactly one new window every time, and the new window came to the front every time: 30 of 30 for `open` in the warm run, set-ups included, 22 of 22 more in the set-ups of the forward run and the probe, and 30 of 30 for the binary. With the instance not running, it started Chrome with exactly one window in that profile, in front, 10 of 10 for `open` and 9 of 9 for the binary. Measured.

**Without `-n`** (`open -b com.google.Chrome --args …`), LaunchServices drops the arguments when the app runs. Not tried, because with the owner's Chrome running it would reach his. Reasoned from `open`'s manual.

**Chrome's dictionary has nothing about profiles** (`sdef`, measured). The window class has `given name`, `name` (the title), `id`, `index`, `bounds`, `closeable`, `minimizable`, `minimized`, `resizable`, `visible`, `zoomable`, `zoomed`, `active tab`, `mode` (normal or incognito) and `active tab index`. Tabs have `id`, `title`, `URL` and `loading`. The application also exposes the bookmarks. No class, property or command names a profile, an account or a user. `make new window` opens in the profile of the last active window: in Chromium's source (`window_applescript.mm`) it takes `AppController.lastProfile`, so the app cannot choose the profile that way.

**A window can be brought forward only by its id.** `set index of window id <id> to 1` followed by `activate` brought the intended window forward 10 of 10, with no new window, in 0.46 s. Setting the index alone did not bring Chrome forward. The window `id` is Chrome's session ID for the window, such as `1485785376`, not the window server's window number. The two match by `bounds`, which agree exactly. So the app can bring back a window it opened itself, if it noted the window's id when it appeared, as the difference between the ids before and after its open command. It cannot find a window the user opened, because nothing tells which profile that window belongs to. Whether a window keeps its id when Chrome restarts and restores it was not tried.

**"Chrome is not running at all."** Measured here as "the throwaway instance is not running": `open -n -b com.google.Chrome --args --profile-directory=<directory>` started Chrome with one window of that profile. For the real case, reasoned: with no Chrome running, the same command starts the owner's Chrome with that profile only. When that profile is set to continue where it left off, Chrome would restore its last windows instead of one new window. Reasoned, not tried.

### Part 3: permissions

| Way | Permission | Measured |
|---|---|---|
| Reading `Local State` | None in `$TMPDIR`. In Chrome's own folder: "App Data" for Google Chrome. Terminal was denied without a prompt | Both |
| `open -n -b com.google.Chrome --args …` | None. Chrome runs as its own responsible process | No prompt in 44 starts and 52 hand-overs on the throwaway, nor in the one run on the owner's Chrome |
| Chrome's binary, started by the caller | None for the call. But Chrome then runs as the caller's child, and macOS holds the caller responsible for Chrome's requests: Chrome's local network discovery showed a Local Network prompt naming **Terminal**, in the first try of `cold … binary`. For the app it would name the app. Hand-overs to a running instance asked for nothing | Yes |
| Apple events to Chrome | Automation, for the sending app and Chrome's bundle ID. One answer covers every Chrome instance, the owner's included | The check returned 0 before the first event: Terminal already had it. No prompt |
| The window server's list without names | None | Yes |

**Permission prompts.** macOS showed one prompt during the spike. No prompt's text could be read from the screen, because that would need Accessibility or Screen Recording, so each is given in English from the system's string tables, with the app's name filled in. The App Data prompt is under Part 1: it did not show either.

- **Local Network**, shown once, during try 1 of `cold … binary`, by `UserNotificationCenter`: "Allow “Terminal” to find devices on local networks?" with "This will allow the app to discover, connect to, and collect data from devices on your networks." It came because Chrome, started as Terminal's child, looked for devices on the network. It was still open on screen when the throwaway stage ended, waiting for the owner's answer.
- **Automation**, not shown here, because Terminal already held it: "“Terminal” wants access to control “Google Chrome”. Allowing control will provide access to documents and data in “Google Chrome”, and to perform actions within that app.", with "Don’t Allow" and "Allow". For the app, its own name stands in for Terminal. Under the hardened runtime, the app also needs the `com.apple.security.automation.apple-events` entitlement and an `NSAppleEventsUsageDescription`, or macOS does not ask at all. Reasoned from `tccd`'s log, which says so for other apps.

**The Keychain.** No Keychain prompt showed. The one throwaway start checked in the log made one `SecItemCopyMatching` call, and the log does not say what it looked for. `--use-mock-keychain` is meant to keep Chrome's cookie encryption away from the "Chrome Safe Storage" item. That the flag worked is reasoned from Chromium's switch, not proven.

### Part 4: what the app can know about a profile's windows

**Nothing per profile.** Measured: the probe read every allowed property of three windows, one per profile, and they differ only in `id`, `index` and `bounds`:

```
windows' id: [1485785376, 1485785369, 1485785362]
windows' index: [1, 2, 3]
windows' givenName: [, , ]
windows' mode: [normal, normal, normal]
windows' minimized: [0, 0, 0]
windows' visible: [1, 1, 1]
windows' bounds: [NSRect: {{264, 33}, {1200, 847}}, NSRect: {{242, 77}, {1200, 847}}, NSRect: {{220, 55}, {1200, 847}}]
window server: 3296 (264.0, 33.0, 1200.0, 847.0); 3292 (242.0, 77.0, 1200.0, 847.0); 3274 (220.0, 55.0, 1200.0, 847.0)
```

- **With Automation:** how many windows Chrome has in all profiles together, and each window's id, order, bounds, and whether it is minimized, visible or incognito. The cost is high: the same permission lets the app read every tab's URL and title and run JavaScript in any page of any profile, and macOS's prompt says so. The app would hold that power even if it read only window ids. `given name` is text the user typed, so the app should not read it either.
- **Without any permission:** the window server's list gives the number of Chrome's on-screen windows, their order and bounds, for all profiles together, because every profile's windows belong to one process. Not their titles, which need Screen Recording.
- **How many windows one profile has:** not possible with any way the card allows.

### What the feature must watch for

- **A profile directory that does not exist creates a new profile.** Measured. The app must check the linked directory against `Local State` before every open, and say the profile is gone when it is missing. Without the App Data permission it cannot check, so it must not open a directory it could not confirm.
- **Every open is a new window.** Ten clicks are ten windows. The app should say "Open a window in <profile>", never "Bring forward", unless it brings back a window it noted.
- **Never start Chrome's binary as the app's child.** macOS then charges the app for Chrome's permissions. `open -n -b`, or `NSWorkspace.openApplication(at:configuration:)` with `createsNewApplicationInstance`, starts Chrome as its own process. The second is reasoned to be the same as the first.
- **A second Chrome process for a moment.** `open -n` starts a second Chrome process that hands its arguments to the running one and ends. The binary's hand-over process ended in 0.21 to 0.22 s.
- **The new window appears on the current desktop.** A window on another desktop or minimized was not tried.

## Ideas not tried, and their cost

- **Naming the app's own windows.** `given name` can be set by Apple events and shows as the window's title, and Chrome should keep it across a restart, which is reasoned. The app could tag the window it opened with the workspace's name and find it again after a restart. It changes what the user sees in Chrome, and needs Automation.
- **A companion extension per profile** with native messaging. The only way found that could list and focus a profile's own windows, the user's included, without Accessibility. It needs an extension installed in every profile and a native messaging manifest written into Chrome's folder.

## Other browsers

Reasoned, nothing tried. **Safari** keeps its profiles in its protected container, has no command-line switch for a profile, and its dictionary has no profile, so neither listing nor opening carries over. **Arc** is built on Chromium, but organises work in spaces, and its dictionary is said to reach spaces by name, which would bring the right space forward. It needs Automation, and Arc is no longer actively developed. **Firefox** lists its profiles in a plain `profiles.ini` and opens one with `-P <name>`, and every running profile is a process of its own. So the app could tell a profile's windows apart by process ID and might bring them forward without any permission, which Chrome does not allow. It is the browser where the idea would carry furthest.

## The owner's real Chrome

The owner said yes on 2026-11-23 to two commands, each run once, from Terminal in the worktree. Nothing else touched his Chrome, its folder or its `Local State`, and no Apple event was sent to his Chrome.

1. **List the profiles:** `swift Spikes/chrome-profiles/profile-names.swift ~/Library/"Application Support"/Google/Chrome/"Local State"`. Result: no profiles listed. The read was denied by macOS (Part 1), and the helper printed only `the file is not a Local State file Chrome wrote: NSError`. It has since been changed to say `cannot read the file` with the error's domain and code. The owner took the denial as the result: no new permission and no second run. Measured.
2. **Open one window in `Default`:** `open -n -b com.google.Chrome --args --profile-directory=Default`. Step 1 could not list `Default`, so the owner confirmed himself that one of his profiles uses that folder, and said yes to one run without the check. Measured, with Terminal in front and his Chrome running:

| | Before | After, 2 s after the command |
|---|---|---|
| His Chrome's on-screen windows | 2 | 2: 1 new, and 1 of the earlier 2 no longer on screen |
| Frontmost app | Terminal | his Chrome |
| The new window is Chrome's front window | | yes |

The command took 0.15 s, and the signals agreed at 0.67 s: Chrome frontmost with the new window in front. So this is a hit for opening: exactly one new window, in front. In the same second the system log shows the desktop of one display switching, so the earlier window most likely went off screen with that switch. Nothing was sent that could close a window, and the owner closes the new window himself. Which profile the window opened in, only the owner can see.

## Recommendation

Written after the stage above.

## Clean up

`chrome-check.swift` stops every throwaway instance itself. Before removing the scratch folder, check that nothing with it runs and look at it, then remove it by its literal path:

```sh
pgrep -f "$S/ud" || echo "nothing runs"
ls "$S" "$S/ud"
rm -r <the scratch folder, written out>
```
