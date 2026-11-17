# Spike: bring the right window forward in VS Code and Cursor

Card #7, phase 0. Whether a command can bring forward the VS Code or Cursor window that holds a given Claude Code session. Window level is enough: selecting the integrated terminal inside the window is not planned.

Tested on macOS 27.2 with three displays, VS Code 1.145.0 and Cursor 3.27.22, with every command sent from a script started in Terminal. The spike's code, the single steps to repeat it and the full results are in [Spikes/editor-focus/README.md](../../Spikes/editor-focus/README.md).

**The main case was never run end to end.** Nobody started a session in an editor's integrated terminal and then focused its window from that session's `SessionStart` line. The guided pass that would have done it was interrupted, and no session was started in the Tester's repeat. The owner accepted the card's items 1 and 4 as met by two halves, measured apart:

- **The hook half**, in card #5 ([claude-hook.md](claude-hook.md)): a session in either editor's integrated terminal names its editor by `__CFBundleIdentifier` and reports its `cwd`.
- **The focus half**, here: `open -b <bundle id> <folder>` brought the window on that folder forward, 10 of 10 per editor in the Tester's repeat.

## How sure each result is

Every result below is one of four kinds, as in the spike's README:

- **measured**: the Developer ran it and read the four signals.
- **repeated**: the Tester ran it again on `0bc8867`, on a new scratch folder with one spike window per editor, and read the same four signals.
- **reasoned**: it follows from VS Code's source. Nobody saw it happen. Cursor is a fork of VS Code and its code was not read, so for Cursor it is one step weaker.
- **not measured**: neither. The pass that would have measured it was interrupted and not repeated.

## The answers

1. **Can a command bring the window forward?** Yes, when the session's folder is exactly the folder a window has open. `open -b <bundle id> <folder>` did it every time: VS Code 13 of 13 and Cursor 2 of 2 measured, then 10 of 10 in each editor repeated, with no new window.
2. **When it cannot.** For any other folder the same command opens a new window. That was measured for a folder no window has, and is reasoned for a subfolder of the window's folder. A remote or container session cannot be matched at all (reasoned).
3. **How fast.** In the Tester's repeat the command took about 0.07 s, and the four signals agreed after about 0.23 s, at worst 0.64 s.
4. **How sure.** Sure only when the folders are equal. Without window names, Accessibility or the editor's own state, none of which the card allows, the app cannot tell which folder a window has open. **When it cannot be sure, the command is an "open a new window" command.** An unwanted window is worse than no focus, and costs about a dozen processes.
5. **Permissions.** None. No Accessibility, no Screen Recording, no Automation of an editor.

## How the two editors are told apart

From card #5:

| Editor | `__CFBundleIdentifier` | Ancestors after the shell |
|---|---|---|
| VS Code | `com.microsoft.VSCode` | `Code Helper` → `Code` |
| Cursor | `com.todesktop.230313mzl4w4u92` | `Cursor Helper: terminal pty-host` → `Cursor` |

- Both set `TERM_PROGRAM=vscode` and the same `VSCODE_*` variables. Neither sets a `CURSOR_*` variable. So `TERM_PROGRAM` names neither editor. The bundle id does.
- The bundle id is also what the focus command takes.

## The focus command

Neither editor has an AppleScript dictionary, so a window is reached through its folder. Three commands were compared:

| Name | Command | Result |
|---|---|---|
| `open` | `open -b <bundle id> <folder>`. LaunchServices sends the folder to the running editor and activates it | **The only one with results** |
| `cli` | The editor's shell command inside the app bundle: `<app>/Contents/Resources/app/bin/code <folder>`, or `…/bin/cursor` | not measured |
| `app` | `open -b <bundle id>`: activate only, with no folder | not measured |

What VS Code does with them, read in its source (`src/vs/code/electron-main/app.ts` and `src/vs/platform/windows/electron-main/windowsFinder.ts`). All reasoned:

- Before it opens anything, it looks for a window whose folder **equals** the folder, ignoring case (`findWindowOnWorkspaceOrFolder`). If one exists, that window is focused.
- There is no check for a folder inside a window's folder. A multi-root workspace window matches only its `.code-workspace` file, never one of its folders.
- If no window matches, `open` and the CLI both prefer a new window. `open` arrives as an `open-file` event, which VS Code opens with the context "dock" after waiting 100 ms for more paths.
- `app` sends a reopen. The editor comes forward with its last active window. When it has no visible window, VS Code opens a new empty one.
- VS Code restores a minimized window before it focuses it (`doFocusWindow` in `windowImpl.ts`).
- `open -b` starts an editor that is not running. The spike refused that case and never saw it.

**Settings that change this.** The defaults were read from both app bundles, and VS Code 1.145 and Cursor 3.27 have the same ones. No user setting was read or changed.

- `window.openFoldersInNewWindow`, default `"default"`. With `"off"`, a folder no window has **replaces the folder of the user's last active window**. That is worse than a new window. A folder that a window already has is focused first under every value.
- `terminal.integrated.cwd`, unset by default. When set, a new terminal starts somewhere other than the window's folder, so the session is a subfolder case from the start.
- `window.nativeTabs`, off by default. When on, windows can be tabs of one window. Not tried.

## How an attempt was counted

After each command, the helper read four signals again and again for up to 6 seconds. An attempt was right only when all four agreed:

1. **The frontmost app**, from LaunchServices (`lsappinfo front`), is the editor the bundle id names.
2. **The editor's frontmost window** is the expected spike window: its first on-screen normal window, at least 300 by 200 points, in the window server's front-to-back list.
3. **Nothing covers it**: the topmost on-screen window over the target's spot is the target, as in card #6.
4. **No new window**: the editor's windows, minimized and on other Spaces included, are the same set as before the command. It looks once more at 2 seconds, because a new window can appear after the right one came forward.

Spike windows were told apart by their window number, noted when each first appeared. No window title was read, and no Accessibility or Screen Recording was used.

## Measured runs

| | VS Code | Cursor |
|---|---|---|
| `open`, measured run. Before each attempt a second spike window, B, was the editor's last active window, and the other editor was in front on the same folder | **Measured:** 10 of 10 to A. The run then stopped at its first attempt to B, when the owner brought another app forward. Command median 0.135 s, worst 0.159 s. Signals agree median 0.306 s, worst 0.328 s, at the first reading every time | not measured |
| `open`, from Terminal in full screen on the same display | **Measured:** 3 of 3, about 0.30 s | **Measured:** 2 of 2, 0.29 and 0.44 s |
| `open`, the Tester's repeat: ten attempts on A, the editor's only spike window, with Terminal in front | **Repeated:** 10 of 10, no new window. Command median 0.074 s, worst 0.146 s. Signals agree median 0.237 s, worst 0.639 s | **Repeated:** 10 of 10, no new window. Command median 0.073 s, worst 0.146 s. Signals agree median 0.232 s, worst 0.603 s |
| `open` with a folder no window has | **Measured:** a new window every time. The number of attempts was not recorded. **Repeated:** 1 of 1, the opening of the spike window | **Measured:** a new window every time, at least twice. Twice it opened on a Space that was not shown, and Cursor did not stay in front. **Repeated:** 1 of 1 |
| `cli`, any case | not measured | not measured |
| `app`, activate only | not measured | not measured |

- In the Tester's repeat, the first attempt in each editor needed a second reading, about 0.6 s. The other nine agreed at the first reading, in 0.22 to 0.31 s.
- The owner's Terminal was in full screen on the display where most spike windows opened. So every focus from Terminal also switched that display's Space.
- Neither `code` nor `cursor` was on PATH on this Mac.

## The card's cases

| Case | Result | Kind |
|---|---|---|
| The main case: a session in the editor's integrated terminal, focused from its `SessionStart` line | The hook half is card #5, the focus half is case 1. The two were never run as one. The owner accepted the two halves | not measured end to end |
| 1. The folder is the window's folder | **Works** with `open`. VS Code 13 of 13 and Cursor 2 of 2, then 10 of 10 in each editor | measured and repeated |
| 2. A subfolder of the window's folder | **Opens a new window.** A window is found only when its folder equals the path. The pass ran the subfolder steps, but their results are lost | reasoned |
| 3. Two windows of the same editor | **Works** in VS Code: in the 10 of 10 run the other spike window was the last active one every time. Cursor is expected to do the same | VS Code measured, Cursor not measured |
| 4a. The window is on another Space | **Works** when the Space in front is a full-screen app's: the display switched to the editor's window, VS Code 3 of 3 and Cursor 2 of 2. A window dragged to another desktop was never tried | full screen measured, another desktop not measured |
| 4b. The window is minimized | **Expected to work.** VS Code restores a minimized window before it focuses it | reasoned |
| 5. The editor's shell command is not installed | **Does not matter for `open`**, which goes through LaunchServices. Everything above was measured with neither command on PATH. The `cli` route calls the command inside the app bundle, so it would not need PATH either, but it has no result | `open` measured, `cli` not measured |
| 6. A remote or container session | **Expected to fail, or to open a new window.** The hook runs inside the container: its `cwd` is a path that does not exist on the Mac, and it has no `__CFBundleIdentifier`. So the session names neither a folder nor an editor. The window's folder is a `vscode-remote://` URI that the hook cannot know. The container steps ran in the pass, but their results are lost, and `probe.sh` was never run in a container window | reasoned |

The hook reports `cwd` with symlinks resolved, such as `/private/var/…`, and a window counts as the same folder only when the path is spelled the same. Whether a window opened on the `/var/…` spelling matches was not measured: in the pass, the two steps for it ended within a second and sent no command.

## The subfolder case: what phase 3 should do

**The command cannot be sure.** Nothing the card allows tells the app which folder a window has open. `open -b <bundle id> <folder>` focuses a window only when one has exactly that folder. In every other case it opens a new window.

The recommendation:

1. Use only the `cwd` of the session's **first** `SessionStart`. A new integrated terminal starts in the window's folder, so this is the best guess the hook has. Never follow a later `cwd`.
2. Send `open -b <bundle id> <cwd>` only when that folder looks like a project root, for example when it holds `.git`. Otherwise send `open -b <bundle id>` alone. It brings the editor forward with its last active window, and opens nothing while the editor has a window.
3. For a remote or container session, the same: activate only, or no focus button. The hook there gives no bundle id (reasoned), so activate only would need the editor from somewhere else.

**How sure: not very.** Rules 1 and 2 are reasoned, and the root-marker test was never tried. It fails both ways:

- A window opened on a parent folder of a repository gets a second window.
- A window on a folder without a marker gets the wrong window in front.
- `terminal.integrated.cwd`, or a `cd` before the session starts, breaks rule 1.

**Only activate only avoids an unwanted window**, because it sends no folder. It has no measured result either.

## The interrupted guided pass

The guided pass was a script that ran every step of the spike in seven parts, one after the other. The owner started it once. Four minutes in, during part 2, the Mac stopped responding and was restarted with the power button. The restart emptied the temporary folder, and the pass's log went with it. The pass was not repeated, at the owner's wish. **The script has been removed.** The spike's README now has single steps, run by hand one at a time.

What the system log shows. It keeps process names and times, not what the spike printed:

- The pass ran for 4 min 10 s and started the helper 28 times.
- It opened about ten editor windows: five in VS Code and at most five in Cursor. That is close to what it was written to open: one window more than planned in VS Code, perhaps one in Cursor, and no loop.
- Each new VS Code window started about 11 helper processes: 56 for 5 windows, 45 of them within one minute of part 2.
- The Mac was deep in swap before the pass. Four new swap files were created in that one minute. Then the disk was full, the system could not create the next one, and it stopped responding 35 s later. There was no kernel panic of its own.

So the spike did not run away, but it was the last push: four windows in under a minute on a Mac with no memory and no disk to spare. How much of the swap was the spike's is not known.

**What this means for phase 3: an unwanted window is not only clutter.** One new editor window starts about a dozen processes with the user's extensions. Never send a folder the app is not sure of in a loop or on a timer.

## Things tried that do not work

- **The folder the terminal started in.** The integrated terminal starts in the window's folder, so the shell's start-up `PWD` would name the window even after a `cd`. But macOS 27.2 shows no other process's environment, not even the user's own: `ps -E` prints the command alone, and `KERN_PROCARGS2` returns 29 bytes with no environment for a `sleep` started in the same shell.

## Ideas not tried, and their cost

| Idea | What it would give | Why not |
|---|---|---|
| Claude Code's IDE lock file under `<profile>/ide/` | The window's workspace folders | It sits in a profile folder and holds an auth token, which the rules put off limits. It exists only while the Claude Code extension is connected |
| `code --status` | Every window's folder names | It prints every window's title too, the user's own included. Window titles are off limits |
| The terminal's `VSCODE_IPC_HOOK_CLI` socket | The extension host of the very window | An internal, undocumented protocol. Its `open` request needs a folder or a file too |
| Opening a file inside the `cwd` with the CLI | VS Code picks the window whose folder holds the file (`findWindowOnFile`), multi-root workspaces included | It opens that file in a tab of the user's window, a visible change |
| `--reuse-window` | No new window | When no window has the folder, it replaces the last active window's folder. Never |

## Permissions

- No Accessibility, no Screen Recording, no Automation of an editor.
- `open -b` goes through LaunchServices and sends no Apple event to the editor.
- The only Apple event was `tell application "Terminal" to activate`, sent from Terminal to itself to set the starting state.
- The window server's list was read without window names.
- Everything was sent from scripts started in Terminal. Not from the menu bar app, and not from a signed build.

## Left on the Mac

At the time of writing, for the owner to clean up as the spike's README says under "Clean up":

- Two spike windows, one per editor, are still open. Close them by hand with File, Close Window.
- The Tester's scratch folder in the temporary folder.
- A Docker volume named `vscode`. Dev Containers shares it between containers, so it was left for the owner.

The spike's Dev Container and its image were removed.

## What was not done

- The main case end to end: a session in the integrated terminal, focused from its own `SessionStart` line.
- The `cli` route and activate only, in any case.
- A subfolder, a minimized window, a window on another desktop and the `/var` spelling of a folder, in either editor.
- Two windows of one editor in Cursor.
- A remote or container session. `probe.sh` was never run.
- `window.openFoldersInNewWindow` set to `"off"`, and `window.nativeTabs`.
- The root-marker rule for the subfolder case.
- An editor that is not running.
- The focus sent from the real menu bar app, or from a signed or hardened build.
- A reading of Cursor's own code.

## For card #8

Card #8 writes `docs/spikes/phase-0.md` across all the spikes and corrects the spec. What this spike says about the spec:

**[docs/spec/feasibility.md](../spec/feasibility.md), "Focus VS Code and Cursor":**

- Verdict "Yes, with caveats". **Confirmed**, with sharper caveats. It works when the session's folder is exactly the window's folder: 10 of 10 per editor.
- "Opening the project folder with the `code` or `cursor` command brings the right window forward." **Corrected.** The command with results is `open -b <bundle id> <folder>`, through LaunchServices, and it needs no shell command on PATH. The `code` and `cursor` commands were **not tested**. And the app knows the session's `cwd`, not the project folder: a folder that is not exactly a window's folder opens a new window.
- Caveat "Decided: window-level focus is enough. Selecting the exact integrated terminal tab would need a companion extension, which is not planned." **Confirmed.** The spike found no other way to the terminal inside a window. The one internal route, the `VSCODE_IPC_HOOK_CLI` socket, is undocumented. The caveats should add: a subfolder opens a new window (reasoned), a remote or container session cannot be focused (reasoned), `window.openFoldersInNewWindow` set to `"off"` makes an unmatched folder replace the user's window (reasoned), and `open -b` starts an editor that is not running.

**"How a session gets linked to its terminal":**

- Step 3, "terminal app, tab identifier." **Confirmed as card #5 said.** For the editors the terminal app is the bundle id, and there is no tab identifier.
- Step 5, "Focus button: the app tells that terminal app to select that tab." **Corrected for the editors.** The app asks LaunchServices to open the session's first `cwd` in the editor the bundle id names, or only activates the editor. No Apple event goes to the editor.
- "No screen scraping, no accessibility tricks." **Confirmed.** Neither was needed.

**"Biggest technical risks", "Terminal focus reliability across four terminal hosts":** **Retired for the exact-folder case** in VS Code and Cursor. What remains: the subfolder case, remote and container sessions, activate only, the main case end to end, and the focus from the menu bar app.

**[docs/spec/plan.md](../spec/plan.md):**

- Phase 0, "Spike 2: same for VS Code and Cursor at window level." **Confirmed, with its limits known**, which is the phase's exit: only an exact folder match is a focus, and the main case was met in two halves, not end to end.
- Phase 3, "Focus adapters: Terminal, iTerm2, VS Code, Cursor." **Confirmed** for the editors: the same command with each editor's bundle id, and the subfolder rules above.
- "Focus button reaches the right terminal at least 9 times out of 10." **Confirmed for the command in the exact-folder case**, 10 of 10 per editor. **Not tested** from the menu bar app, with real sessions, or over a month of use. For the editors it holds only as often as a session's folder is its window's folder. Activate only brings the editor forward, but not always the right window.

**[docs/spec/decisions.md](../spec/decisions.md):**

- Row "VS Code and Cursor", window level is enough and no companion extension. **Confirmed.** Window level was reached without an extension.
- Row "Release details", adapters built first for VS Code and Cursor. **Confirmed.** Both can be built, with the limits above.
- Row "Every part works alone". **Confirmed** for a missing shell command: `open` does not need it. A session that names no editor, such as a container session, gets no focus button, as card #5 said for an unknown terminal. **Not tested:** an editor that is not running. `open -b` would start it, so phase 3 should check that the editor runs before it sends anything.
- The assumption "A hook can tell which terminal tab it runs in, on all four terminal hosts." **Corrected** by card #5 for the editors: the hook names the editor, not the tab. New here, and reasoned: a container session names neither.

**Other spec pages this spike touches:**

- [docs/spec/tech-stack.md](../spec/tech-stack.md), "Terminal, iTerm2, VS Code, Cursor: AppleScript and CLI." **Corrected** for the editors: neither has an AppleScript dictionary, and the command with results is `open -b`, not the CLI.
- [docs/spec/dev-setup.md](../spec/dev-setup.md), "Automation, once per terminal app." The editors needed none here, from scripts in Terminal.
- [docs/spec/design.md](../spec/design.md), Settings, Sessions, "Terminals": "Each shows whether macOS has allowed the app to control it, with an 'Allow' button." VS Code and Cursor needed no such permission here.
- [docs/spec/overview.md](../spec/overview.md), "focused at window level only", and [docs/spec/features.md](../spec/features.md), "the right window in VS Code and Cursor." **Confirmed**, with the subfolder limit.

**For phase 3's code:**

- Take the editor from `__CFBundleIdentifier`, never from `TERM_PROGRAM`.
- Focus with `open -b <bundle id> <folder>` only under the subfolder rules above. Otherwise activate only, or no focus button.
- Check that the editor is running before sending anything.
- Never send a folder the app is not sure of in a loop or on a timer.

**Still open:**

- The main case end to end, sent from the menu bar app.
- The subfolder rule, a minimized window and another desktop, measured.
- Activate only and the `cli` route.
- Cursor beyond the exact-folder case.
- Remote and container sessions.
- The `/var` spelling of a folder.
