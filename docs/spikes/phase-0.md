# Phase 0: what the spikes found

Card #8. A summary across the three phase 0 spikes. The steps, the raw results and the details are in the spike notes, and every number here links to its source in one of them:

- [claude-hook.md](claude-hook.md), card #5: what a Claude Code hook tells the app about a session.
- [terminal-focus.md](terminal-focus.md), card #6: bringing the exact tab forward in iTerm2 and Terminal.
- [editor-focus.md](editor-focus.md), card #7: bringing the right window forward in VS Code and Cursor.

## The three answers

### What works

- A Claude Code hook reports every state the session list needs: working, waiting for you, finished and gone. It also names the session's profile and terminal app, and in Terminal and iTerm2 its tab ([card #5](claude-hook.md#the-answers)).
- The exact tab comes forward in iTerm2 and in Terminal, 120 of 120 per app ([card #6](terminal-focus.md#measured-runs)).
- The VS Code or Cursor window comes forward when the session's folder is exactly the folder the window has open, 10 of 10 per editor ([card #7](editor-focus.md#measured-runs)).
- The hook can be installed into a settings file and removed again, and a file that survives a two-space JSON round trip comes back byte-identical ([card #5](claude-hook.md#on-a-real-profile)).
- No Accessibility and no Screen Recording, for any of the four apps. The editors need no Automation either ([card #6](terminal-focus.md#permissions), [card #7](editor-focus.md#permissions)).

### What does not work

- After a denied permission or an Esc, no event comes at all, so a session would stay "waiting" or "working" ([card #5](claude-hook.md#event-orders-for-the-basic-cases)).
- In VS Code and Cursor, a folder that is not exactly a window's folder, such as a subfolder, opens a new window instead of focusing one. Reasoned from VS Code's source, not measured ([card #7](editor-focus.md#the-cards-cases)).
- A remote or container session in an editor names neither a folder on the Mac nor an editor, so it cannot be focused. Reasoned ([card #7](editor-focus.md#the-cards-cases)).
- With VS Code's `window.openFoldersInNewWindow` set to `"off"`, a folder no window has replaces the folder of the user's last active window. Reasoned. `window.nativeTabs` was not tried ([card #7](editor-focus.md#the-focus-command)).
- Only the editor window comes forward, never the terminal inside it ([card #7](editor-focus.md#for-card-8)).
- Nothing comes forward while the screen is locked ([card #6](terminal-focus.md#a-locked-screen)).
- A settings file that does not come back byte for byte from a two-space JSON round trip, such as a hand-formatted one, cannot be given back unchanged. The spike's installer refuses it ([card #5](claude-hook.md#what-the-spike-did)).

### What phase 3 can rely on

**As it is:**

- The events and what each one means, below, with the owner's rule that only a subagent, a workflow or a teammate keeps a session working after its main thread stops ([card #5](claude-hook.md#subagents-when-the-main-thread-stops-before-its-subagents)).
- The profile rule and the handles for each app, below.
- The two focus commands for Terminal and iTerm2 ([card #6](terminal-focus.md#the-focus-commands)), and `open -b <bundle id> <folder>` for an editor window on exactly that folder ([card #7](editor-focus.md#the-focus-command)).
- The rules for the installer ([card #5](claude-hook.md#rules-for-phase-3s-installer)), and the fields the hook sends and must never send ([card #5](claude-hook.md#the-event-format-and-the-fields-the-app-uses)).

**With a workaround:**

- A turn that ends without an event needs a fallback. Which one is an open question below.
- Two subagents that finish close together make the state flicker. A debounce of about two seconds covers it ([card #5](claude-hook.md#subagents-when-the-main-thread-stops-before-its-subagents)).
- A tty is reused at once. Before every focus in Terminal, the app checks that the session's `claude` process still holds the tty ([card #6](terminal-focus.md#the-handle-for-each-app)).
- Several profiles can share one settings file through a symlink. The hook is installed once per file, into the link's target, and the user is told which profiles it reaches ([card #5](claude-hook.md#rules-for-phase-3s-installer)).
- A window on another Space or in full screen comes forward with a visible jump, as the owner judged by eye ([card #6](terminal-focus.md#awkward-cases)). The app does not focus while the screen is locked.
- An editor session in a subfolder: send the `cwd` of the session's first `SessionStart` only when it looks like a project root, otherwise only activate the editor. Reasoned, and the root-marker test was never tried ([card #7](editor-focus.md#the-subfolder-case-what-phase-3-should-do)).
- `open -b` is expected to start an editor that is not running. The spike never saw it, so the app checks first ([card #7](editor-focus.md#the-focus-command)).
- Automation: the app asks for it itself, and when it is denied the Focus button is left out ([card #6](terminal-focus.md#for-card-8)).

**Off the table:**

- Selecting the integrated terminal inside an editor window. It would need a companion extension, which is not planned ([card #7](editor-focus.md#for-card-8)).
- Focusing a remote or container session. It gets no Focus button ([card #7](editor-focus.md#for-card-8)).
- Finding out which folder an editor window has open. Window titles, Accessibility, `code --status` and Claude Code's IDE lock file would tell, but each needs what the rules or the spec rule out: window titles, Accessibility, or a file in a profile folder that holds an auth token. `--reuse-window` can replace the folder of the user's window ([card #7](editor-focus.md#ideas-not-tried-and-their-cost)).
- Reading another process's environment, such as the start-up folder of an editor's terminal. macOS 27.2 shows none ([card #7](editor-focus.md#things-tried-that-do-not-work)).
- Naming the profile in the hook's command at install time. It cannot work on a shared settings file ([card #5](claude-hook.md#which-profile)).
- Writing to a tty. A reused tty would send it to someone else's tab ([card #6](terminal-focus.md#safety-work-from-the-review)).
- Sending an editor a folder the app is not sure of in a loop or on a timer. One new VS Code window starts about 11 helper processes ([card #7](editor-focus.md#the-interrupted-guided-pass)).

## How sure each result is

Card #7 names four levels: **measured** by the Developer, **repeated** by the Tester, **reasoned** from VS Code's source without being seen, and **not measured** ([card #7](editor-focus.md#how-sure-each-result-is)). Across the three spikes:

- **Card #5** was measured in a scratch project in Terminal and iTerm2, and repeated by the Tester with the same order and timings, within one to three seconds. VS Code and Cursor were run by hand. A real settings file was changed once, for 50 seconds ([card #5](claude-hook.md), [the real profile](claude-hook.md#on-a-real-profile)). Until a dialog that blocked Apple events was closed, the subagent cases and the Esc case ran in a pseudo-terminal with a reset environment, and iTerm2 was tested only afterwards ([what went wrong](claude-hook.md#gaps-and-what-failed)).
- **Card #6** was measured and repeated, two rounds each ([card #6](terminal-focus.md)). **The tabs held plain shells, not live Claude Code sessions.** Card #5 proved that the hook's handles equal what each terminal's AppleScript reports, so the two halves meet at the handle ([what was not done](terminal-focus.md#what-was-not-done)). Another Space and full screen were judged by the owner by eye, not by the three signals ([awkward cases](terminal-focus.md#awkward-cases)).
- **Card #7's main case was never run end to end.** Nobody started a session in an editor's integrated terminal and focused its window from that session's `SessionStart` line. The owner accepted it in two halves: the hook half from card #5 and the focus half from card #7 ([card #7](editor-focus.md)). The exact-folder case is measured and repeated. The subfolder, minimized and container cases are reasoned, and one step weaker for Cursor, whose code was not read. Activate only and the `cli` route are not measured ([card #7](editor-focus.md#the-cards-cases)).
- **Nothing was sent from the real menu bar app or from a signed build.** Every Apple event and every `open -b` came from scripts started in Terminal ([card #6](terminal-focus.md#permissions), [card #7](editor-focus.md#permissions)).
- In iTerm2, which tab shows inside the window rests on iTerm2's own `current session` alone. The window server sees only the window ([card #6](terminal-focus.md#how-an-attempt-was-counted)).

**Tested with:** Claude Code 2.1.326 ([card #5](claude-hook.md)). macOS 27.2 on a Mac with three displays, iTerm2 3.7.7 and Terminal 2.15 ([card #6](terminal-focus.md)). VS Code 1.145.0 and Cursor 3.27.22 ([card #7](editor-focus.md)). Card #5 names no macOS version.

## The event format

Claude Code passes each event to the hook as one JSON object on standard input. Every event carries `session_id`, `transcript_path`, `cwd`, `hook_event_name` and `scratchpad_dir` ([card #5](claude-hook.md#events-and-what-each-one-means-for-the-app)).

| State | Event |
|---|---|
| Registered | `SessionStart` |
| Working | `UserPromptSubmit`. It also comes, with a `<task-notification>` prompt nobody typed, when finished background work wakes the main thread |
| Waiting for you | `PermissionRequest`, about 2 s after the prompt, and `Notification` with `permission_prompt`, about 6 s after the request. Sandbox network prompts send only the second |
| Finished | `Stop`, unless its `background_tasks` still lists a subagent, a workflow or a teammate. `StopFailure` means finished with an error |
| Gone | `SessionEnd` |

- The timings are from [card #5](claude-hook.md#events-and-what-each-one-means-for-the-app).
- The app ignores `Notification` with `idle_prompt`, which comes 60 s after the last `Stop`, and `auth_success` ([card #5](claude-hook.md#event-orders-for-the-basic-cases)). It also ignores the `SubagentStop` with an empty `agent_type` that Claude Code's own agent sends.
- Subagents run in the background by default since Claude Code 2.1.302, which is why a `Stop` alone no longer means finished ([card #5](claude-hook.md#subagents-when-the-main-thread-stops-before-its-subagents)).
- Phase 3's hook tool must exit at once when the app is not running, print nothing, finish well under 100 ms, and never send content or the whole environment. These are targets, not measurements ([card #5](claude-hook.md#release-and-dev), [the fields](claude-hook.md#the-event-format-and-the-fields-the-app-uses)). The only time measured was the spike hook's 0.16 s per call, 0.12 s of it for listing every process with `ps -A`. One `sysctl` call for the parent's tty can replace that ([card #5](claude-hook.md#which-terminal-and-which-tab)).

## How a session's profile, terminal app and tab are identified

- **Profile:** `CLAUDE_CONFIG_DIR` when it is set, otherwise the part of `transcript_path` before `/projects/`, otherwise the default profile. `CLAUDE_CONFIG_DIR` came through unchanged on 50 of 50 events in the Tester's run, and a shared settings file does not change it ([card #5](claude-hook.md#which-profile)). The default profile was seen only in the owner's Cursor run, never through a terminal the spike drove. Whether a profile folder already describes its live sessions was not looked at: the owner left it out, because it means reading other files in the profile folder ([card #5](claude-hook.md#what-was-not-done)).
- **Terminal app:** `__CFBundleIdentifier`. `TERM_PROGRAM` is `vscode` in both editors, so it names neither ([card #5](claude-hook.md#which-terminal-and-which-tab)).
- **Tab:** the hook has no tty of its own. Its parent is always the `claude` process, whose pid Claude Code exports as `CLAUDE_PID`, and the two matched in 171 of 171 events ([card #5](claude-hook.md#which-terminal-and-which-tab)).
  - iTerm2: the UUID after the colon in `ITERM_SESSION_ID`. It equals the session's AppleScript `unique ID`, is never given to another session, and kept matching for over two hours through minimize, hide, another Space and full screen ([card #6](terminal-focus.md#the-handle-for-each-app)).
  - Terminal: the tty of the `claude` process, which equals the tab's AppleScript `tty`. AppleScript does not show `TERM_SESSION_ID`. The tty is reused at once after the tab closes, so the app keeps it together with the `claude` pid and the session id ([card #6](terminal-focus.md#the-handle-for-each-app)).
  - VS Code and Cursor: no tab identifier. The window is found by the session's folder ([card #7](editor-focus.md#the-focus-command)).
  - Any other terminal: no handle, so the session is listed without a Focus button ([card #5](claude-hook.md#which-terminal-and-which-tab)).

## Reliability numbers

| What | Result | Source |
|---|---|---|
| The exact tab forward, iTerm2 | 120 of 120. The card asked for 9 out of 10 | [card #6](terminal-focus.md#measured-runs), [the ask](terminal-focus.md#the-answers) |
| The exact tab forward, Terminal | 120 of 120 | [card #6](terminal-focus.md#measured-runs) |
| Focus command, iTerm2 and Terminal | About 0.28 s. Medians 0.277 s in iTerm2 and 0.273 s in Terminal | [card #6](terminal-focus.md#the-answers), [timings](terminal-focus.md#measured-runs) |
| Tab in front, all signals agree | About 0.45 s, at the first reading every time | [card #6](terminal-focus.md#the-answers) |
| Minimized terminal window | About 0.8 s, because of the Dock animation | [card #6](terminal-focus.md#the-answers) |
| A tab that no longer exists | Nothing changes, exit 1 after about 0.20 s | [card #6](terminal-focus.md#awkward-cases) |
| Editor window forward, exact folder | VS Code 13 of 13 and Cursor 2 of 2 measured, then 10 of 10 per editor repeated, with no new window | [card #7](editor-focus.md#the-answers) |
| Editor command | About 0.07 s. All signals agree after about 0.23 s, at worst 0.64 s | [card #7](editor-focus.md#the-answers) |
| `CLAUDE_PID` equals the hook's parent | 171 of 171 events | [card #5](claude-hook.md#which-terminal-and-which-tab) |
| Install on the shared settings file | Installed for 50 seconds, byte-identical after uninstall | [card #5](claude-hook.md#on-a-real-profile) |
| The spike installer's self-test | 30 cases, all pass | [card #5](claude-hook.md#what-the-spike-did) |

### Every case that failed

- No event after a denied permission or an Esc ([card #5](claude-hook.md#gaps-and-what-failed)).
- The state flickers when two subagents finish close together ([card #5](claude-hook.md#gaps-and-what-failed)).
- Terminal and iTerm2 refused Apple events with error −1712 while a dialog was open on screen ([card #5](claude-hook.md#gaps-and-what-failed)).
- Typed by script into Terminal, `/exit` was completed to a different slash command, and a long prompt stayed in the input box ([card #5](claude-hook.md#gaps-and-what-failed)).
- The first Cursor run did not reach the log ([card #5](claude-hook.md#gaps-and-what-failed)).
- Claude Code refused a long plain `sleep` in a foreground command, so the subagents used a `pause` script. The model ignored "wait for it" until fork mode was off and `run_in_background` was named ([card #5](claude-hook.md#gaps-and-what-failed)).
- A wait loop with a broken condition cost one run of case c, which was repeated ([card #5](claude-hook.md#gaps-and-what-failed)).
- The first review rejected the spike's installer: it could empty the settings file and overwrite its backup, and its log could hold the first word of a prompt that started with `<`. Fixed in round 2 ([card #5](claude-hook.md#gaps-and-what-failed)). Its uninstall, pointed at a file it never installed into, still rewrites that file, a low-severity finding left unfixed ([card #5](claude-hook.md#rules-for-phase-3s-installer)).
- While the screen was locked, `activate` blocked for about 2.1 s and nothing came forward. Round 1 of card #6 lost about an hour to it ([card #6](terminal-focus.md#a-locked-screen)).
- A window another app parked outside every display made every attempt look wrong, until the check looked at the target's spot instead of the global window list ([card #6](terminal-focus.md#several-displays)).
- Hiding another app by script failed, so hidden became a hand step ([card #6](terminal-focus.md#awkward-cases)).
- The first review of card #6 rejected the helper, which trusted a recorded Terminal tty without checking the pid ([card #6](terminal-focus.md#safety-work-from-the-review)).
- A folder no window has opened a new editor window every time. Twice Cursor opened it on a Space that was not shown and did not stay in front ([card #7](editor-focus.md#measured-runs)).
- Card #7's measured run stopped at its first attempt on the second window, when another app came forward ([card #7](editor-focus.md#measured-runs)).
- Card #7's guided pass was interrupted after 4 min 10 s, when the Mac, already deep in swap, stopped responding and was restarted. Its log was lost, with the results of the subfolder and container steps ([card #7](editor-focus.md#the-interrupted-guided-pass)). The two `/var` steps sent no command ([card #7](editor-focus.md#the-cards-cases)).

## macOS permissions

| App | Permission | For what |
|---|---|---|
| Terminal | Automation | Selecting the tab ([card #6](terminal-focus.md#permissions)) |
| iTerm2 | Automation | Selecting the session and its tab ([card #6](terminal-focus.md#permissions)) |
| VS Code, Cursor | None | `open -b` goes through LaunchServices and sends the editor no Apple event ([card #7](editor-focus.md#permissions)) |

- Neither Accessibility nor Screen Recording was used ([card #6](terminal-focus.md#permissions), [card #7](editor-focus.md#permissions)).
- Automation belongs to the app that sends the events. In the spikes that was Terminal, which already had it, so no prompt appeared. In phase 3 the app sends them itself, so macOS asks it once per terminal app, and asks the Dev build again, because it is a separate app ([card #6](terminal-focus.md#permissions)).
- Not tested: the events from the menu bar app, what a signed, hardened build needs to send them (the `NSAppleEventsUsageDescription` text and the automation entitlement), and what happens when the user denies Automation ([card #6](terminal-focus.md#for-card-8)).

## Phase 0's exit line

"You can build and run from Xcode and from the command line, and the focus trick is proven or its limits are known" ([plan.md](../spec/plan.md#phase-0-setup-and-risk-spikes)).

- **The focus trick:** proven for Terminal and iTerm2. Its limits are known for VS Code and Cursor: only an exact folder match is a focus, and the main case was met in two halves, not end to end.
- **Build and run:** confirmed by this card's Tester from the command line, and by the owner from Xcode.

## The spike code

The code stays under [Spikes/](../../Spikes/) as a reference, next to each spike's README with its steps. It is not app code, and no target builds it: `project.yml` builds only `Apps/Mac` and `Tools/dontburn-hook`. It must not be lifted into the app as it is. For one, `focus-check.swift` compiles only in Swift 5 mode ([card #6](terminal-focus.md#for-card-8)).

## Open questions for the owner

Merged from the three "Still open" lists, keeping those a phase 3 task depends on:

1. Which fallback ends a turn that sends no event: a `PostToolUse` hook on every tool, the transcript's modification time, or a timeout ([card #5](claude-hook.md#for-card-8))?
2. What does the installer do with a settings file that does not survive the round trip, such as a hand-formatted one ([card #5](claude-hook.md#for-card-8))?
3. Do running sessions pick up the installed hook without a restart? If not, the installer has to say so ([card #5](claude-hook.md#for-card-8)).
4. Reading a session's title and last activity from its transcript was not tried. The spike confirmed the path and never read one ([card #5](claude-hook.md#for-card-8)).
5. The focus sent from the menu bar app, from a signed and hardened build, and with Automation denied ([card #6](terminal-focus.md#for-card-8), [card #7](editor-focus.md#for-card-8)).
6. The editor main case end to end, from a live session to its window, sent from the menu bar app ([card #7](editor-focus.md#for-card-8)).
7. The editor subfolder rule: is a root marker such as `.git` good enough, or should the app only activate the editor whenever the folder is not certain? Neither was measured, and neither were a minimized window and another desktop ([card #7](editor-focus.md#the-subfolder-case-what-phase-3-should-do)).
8. Activate only and the `cli` route, and Cursor beyond the exact-folder case ([card #7](editor-focus.md#for-card-8)).
9. Remote and container sessions: no Focus button, or more ([card #7](editor-focus.md#for-card-8))?
10. Whether a window opened on the `/var` spelling of a folder matches the hook's `cwd`, which has symlinks resolved ([card #7](editor-focus.md#the-cards-cases)).
11. The events of "Move to background and exit", which keeps a session alive without a terminal, and the `resume`, `clear` and `compact` sources of `SessionStart` ([card #5](claude-hook.md#for-card-8)).
12. Whether `workflow` and `teammate` entries look as Claude Code's documentation says ([card #5](claude-hook.md#for-card-8)).
13. A split pane in iTerm2 ([card #6](terminal-focus.md#for-card-8)).
14. Settings, Sessions in [design.md](../spec/design.md#sessions) and the prototype: "Terminals" shows an "Allow" for VS Code and Cursor, which need no permission, and each profile has its own "Install hook" button, though one install reaches every profile that shares the settings file ([card #5](claude-hook.md#rules-for-phase-3s-installer)). What should these show?

Left open, with no phase 3 task depending on them: whether `activate` raises every window of the terminal, and another Space with the Space setting off ([card #6](terminal-focus.md#for-card-8)).
