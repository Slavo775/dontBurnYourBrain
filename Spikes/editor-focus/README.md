# Spike: bring the right window forward in VS Code and Cursor

Card #7. Throwaway code that answers one question: can a command bring forward the VS Code or Cursor window that holds a given Claude Code session? Window level is enough. It is not part of the app, not in `project.yml` and not built by the check. The findings go to `docs/spikes/`.

| File | What it is |
|---|---|
| `editor-check.swift` | Runs one focus command, a measured run, or the main case from a logged session, and reads four signals after each. Notes every window that appears during an attempt by its window number, so the spike knows which windows it opened. Run it with `swift`, nothing to build |
| `probe.sh` | For the container case only, see "Single steps". Runs inside a Dev Container window's terminal. Writes where that terminal runs, the names of the editor's environment variables and its parent processes to `probe-<editor>.txt` |

The session's own hook is the one from card #5: `Spikes/claude-hook/spike-hook.sh` with `Spikes/claude-hook/settings.local.json`.

## The commands compared

Neither editor has an AppleScript dictionary, so a window is reached through its folder. Three commands:

| Name | Command | What it is |
|---|---|---|
| `open` | `open -b <bundle id> <folder>` | LaunchServices sends the folder to the running editor and activates it |
| `cli` | `<app>/Contents/Resources/app/bin/code <folder>`, or `…/bin/cursor` | The editor's own shell command, called inside the app bundle. `--folder-uri <uri>` for a remote window |
| `app` | `open -b <bundle id>` | Activates the editor without a folder. Its last active window comes first |

The bundle ids are `com.microsoft.VSCode` and `com.todesktop.230313mzl4w4u92`. They come from `__CFBundleIdentifier` in the hook's environment, which is how the two editors are told apart: both set `TERM_PROGRAM=vscode` and the same `VSCODE_*` variables, and neither sets a `CURSOR_*` variable (card #5). The ancestors differ too: `Code Helper` → `Code`, and `Cursor Helper: terminal pty-host` → `Cursor`.

What each editor does with them, from VS Code's source (`src/vs/code/electron-main/app.ts` and `src/vs/platform/windows/electron-main/windowsFinder.ts`). Cursor is a fork of VS Code, and its code was not read:

- `open` arrives as an `open-file` event. VS Code waits 100 ms for more paths, then opens them with the context "dock" and `preferNewWindow: true`. The CLI opens with the context "cli" and also prefers a new window.
- Before that, both look for a window whose folder **equals** the folder (`findWindowOnWorkspaceOrFolder`), ignoring case. If one exists it is focused. There is no containment check, and a multi-root workspace window matches only its `.code-workspace` file, never one of its folders.
- `app` sends a reopen. When the editor has no visible window, VS Code opens a new empty one (`app.on('activate')`).

### Settings that change this

From VS Code's settings descriptions (`src/vs/workbench/browser/workbench.contribution.ts`). The defaults were read from both app bundles, and VS Code 1.145 and Cursor 3.27 have the same ones. No setting was read from the owner's settings or changed.

| Setting | Default | What it changes for the focus |
|---|---|---|
| `window.openFoldersInNewWindow` | `"default"`: "Folders will open in a new window unless a folder is picked from within the application" | `"on"`: a new window, the same as the default here. `"off"`: "Folders will replace the last active window", so a folder no window has **replaces the folder of the user's last active window**. Worse than a new window. A folder that a window already has is focused first under every value |
| `window.openFilesInNewWindow` | `"off"`: files open in the window that has their folder, or the last active window, except that on macOS a file opened through the Dock, which `open` counts as, opens in a new window | Only the file idea below |
| `terminal.integrated.cwd` | unset: a new terminal starts in the window's folder | When set, a session's `cwd` differs from the window's folder from the start: the subfolder case |
| `window.nativeTabs` | `false` | When on, windows can be tabs of one window. Not tried |

## Before a run

- **Open as few windows as you can, one step at a time.** A new editor window starts about a dozen processes with the owner's extensions. A script that ran every step in a row once opened about ten windows in four minutes on a Mac that was short of memory and disk, and the Mac stopped responding. See "The interrupted pass" under Results. That script has been removed. Run single steps by hand and read each result before the next. A `try` on a window that is already open is the safe way to repeat a result.
- **Focus will jump** between VS Code, Cursor and Terminal with every attempt, and the screen can slide between Spaces. Keep hands off the keyboard and the mouse while a step runs. The first measured run here stopped when the owner, still at work, brought another app forward.
- **Unlock the screen, and keep it unlocked.** `editor-check.swift` refuses to run while it is locked.
- **Both editors must already be running.** The spike never starts one: `open -b` would launch an editor that is not running, and the helper refuses then.
- **No permissions.** No Accessibility, no Screen Recording, no Automation of an editor. The only Apple event is `tell application "Terminal" to activate`, sent from Terminal to itself. The window server's list is read without window names.
- Never install `code` or `cursor` into PATH. The CLI is called inside the app bundle.

## Set up

From the repository root:

```sh
S=$(cd "$(mktemp -d -t dontburn-editor)" && pwd -P)
mkdir -p "$S/acme-web/packages/api" "$S/acme-web/packages/web" "$S/globex-app" "$S/acme-web/.claude" "$S/acme-container/.devcontainer"
cp Spikes/claude-hook/spike-hook.sh "$S/"
cp Spikes/claude-hook/settings.local.json "$S/acme-web/.claude/"
cp Spikes/editor-focus/probe.sh "$S/acme-container/"
echo '{ "name": "acme-container", "image": "debian:bookworm-slim" }' > "$S/acme-container/.devcontainer/devcontainer.json"
echo "$S"
```

`pwd -P` matters: the hook reports the session's `cwd` with symlinks resolved, `/private/var/…`, and a window counts as the same folder only when the path is spelled the same. Note whether `debian:bookworm-slim` was there before (`docker image inspect debian:bookworm-slim`), so the clean-up removes it only when the spike pulled it.

## How an attempt is counted

After each command, `editor-check.swift` reads four signals, again and again for up to 6 seconds. An attempt is right only when all four agree:

1. **The frontmost app**, from LaunchServices (`lsappinfo front`), is the editor the bundle id names.
2. **The editor's frontmost window**: its first on-screen normal window (layer 0, at least 300 by 200 points) in the window server's front-to-back list is the expected spike window.
3. **Nothing covers it**: the topmost on-screen window over the target's spot is the target, as in card #6.
4. **No new window**: the editor's windows, minimized and on other Spaces included, are the same set as before the command. It looks once more at 2 seconds, because a new window can appear after the right one came forward.

Spike windows are told apart by their window number, noted in `<scratch>/windows` when each first appears. The output names targets (`A` = `acme-web`, `B` = `globex-app`, `api`, `web`, `container`) and spike windows, never a path outside the scratch folder, a window title or a window of the owner's (it says `other`).

`measure` makes ten attempts to A and ten to B, or the number given, 1 to 20. It needs the spike windows A and B in that editor, and it stops at the first attempt that opens a new window. Before each one, the other spike window is made the editor's last active window, and the other editor's window on the same folder is put in front. So every attempt also covers two windows of one editor, and one folder open in both editors at once. `try` starts from B (or A) as the last active window when that spike window is open, with Terminal in front.

The helper's exit status: 0 when the step is done. 1 when an expected window was named and the verdict is not `RIGHT`, that is `WRONG` or `NEW WINDOW`, or when `measure` stopped at a new window. 2 when it refused the arguments or the starting state: a locked screen, an editor that is not running, a spike window that is not open. So a caller can stop on anything but 0.

## Single steps

There is no script that runs the steps in a row. Each step is one command, run by hand from the repository root in Terminal:

```sh
H=Spikes/editor-focus/editor-check.swift
swift $H try "$S" vscode open A      # opens the spike window on acme-web. A new window, once per editor
swift $H try "$S" vscode open A A    # the focus itself: the last word names the window that must come forward
swift $H windows "$S"                # which noted windows are still open
```

One spike window per editor, A on `acme-web`, is enough for the folder case and for the main case. Steps that open a window are marked. Run one of those only when its result is wanted, and never two at once.

| Case | Step | Opens a window |
|---|---|---|
| The folder is the window's folder | `try "$S" <editor> open A A`, or `cli`, or `app` | no |
| The main case, from a logged session | See below | no |
| A subfolder | `try "$S" <editor> open api`, or `cli web` | yes, when the reasoning under Results holds |
| Two windows of one editor, and one folder in both editors | `try "$S" <editor> open B` once, then `measure "$S" <editor> open [attempts]` | yes, B |
| The window is minimized | Minimize the acme-web window by hand, then `try "$S" <editor> open A A` | no |
| The window is on another desktop | Drag the acme-web window to another desktop in Mission Control, come back, then `try "$S" <editor> open A A` and watch the screen | no |
| The `/var` spelling of the folder | `try "$S" <editor> open B-var B`, with B open | not known |
| A dev container | `try "$S" <editor> cli container` opens the Dev Container window and starts a container, so Docker must be running. When it has connected, type `sh probe.sh <editor>` in that window's terminal and read `<scratch>/acme-container/probe-<editor>.txt`. Then `try "$S" <editor> open container-host` and `cli container container` | yes, and a container |

**The main case from a logged `SessionStart` line.** With the spike window A open in the editor:

1. In that window, open the integrated terminal (Terminal, New Terminal) and start a session, with `CLAUDE_CONFIG_DIR=<profile folder>` in front for a profile:
   `CLAUDE_CODE_IDE_SKIP_AUTO_INSTALL=1 command claude --model haiku --setting-sources project,local --permission-mode default`
   The hook from card #5 appends a `SessionStart` line to `<scratch>/events.jsonl`.
2. In Terminal: `swift $H session "$S" open`. It reads the last `SessionStart` line, picks the editor by `__CFBundleIdentifier`, and sends the focus command for the line's `cwd`. It exits 0 only when the spike window on that folder came forward. A `cwd` that no spike window has open is sent as it is, and opens a new window.
3. Type `/exit` in the session.

## Results

Measured on macOS 27.2 with three displays, VS Code 1.145.0 and Cursor 3.27.22, sent from scripts started in Terminal. The owner's Terminal was in full screen on the display where most spike windows opened, so every focus from Terminal also switched that display's Space.

**The guided pass was not finished, and its log is lost.** The pass was a script, `hand-steps.sh`, that ran every step in seven parts, one after the other. It has been removed since, and the single steps above replace it. The owner started it once. Four minutes in, during part 2, the Mac stopped responding and was restarted with the power button. The restart emptied the temporary folder, and the pass's log and `windows` went with it. The pass was not repeated, at the owner's wish. So every result below is one of four kinds, and says which:

- **measured**: the Developer ran it before the pass and read the four signals.
- **repeated**: the Tester ran it after the pass, on a new scratch folder with one spike window per editor, and read the same four signals.
- **reasoned**: it follows from VS Code's source. Nobody saw it happen. Cursor's code was not read, so for Cursor it is one step weaker.
- **not measured**: neither. The reason is always the same: the pass that would have measured it was interrupted and not repeated.

### What was measured

| | VS Code | Cursor |
|---|---|---|
| `open`, measured run. B was the editor's last active window, and the other editor was in front on the same folder | 10 of 10 to A, then stopped at B 1 when the owner brought another app forward. Command median 0.135 s, worst 0.159 s. Signals agree median 0.306 s, worst 0.328 s, at the first reading every time | not measured |
| `open`, from Terminal in full screen on the same display | 3 of 3 right, about 0.30 s | 2 of 2 right, 0.29 and 0.44 s |
| `open`, the Tester's repeat: ten attempts per editor on A, the editor's only spike window, with Terminal in front | **repeated:** 10 of 10 right, no new window. Command median 0.074 s, worst 0.146 s. Signals agree median 0.237 s, worst 0.639 s | **repeated:** 10 of 10 right, no new window. Command median 0.073 s, worst 0.146 s. Signals agree median 0.232 s, worst 0.603 s |
| `open` with a folder no window has | A new window on every attempt. The number of attempts was not recorded. **Repeated:** 1 of 1, the opening of the spike window | A new window on every attempt, at least two. The exact number was not recorded. Twice it opened on a Space that was not shown, and Cursor did not stay in front. **Repeated:** 1 of 1, the opening of the spike window |
| `cli`, any case | not measured | not measured |
| `app` (activate only) | not measured | not measured |

In the Tester's repeat, the first attempt in each editor needed a second reading, about 0.6 s. The other nine agreed at the first reading, in 0.22 to 0.31 s.

### The card's cases

| Case | Result | Kind |
|---|---|---|
| The main case: a session started in the editor's integrated terminal, focused from the hook's `SessionStart` line | The two halves are measured apart: the hook tells the editors apart by `__CFBundleIdentifier` and reports the `cwd` (card #5), and `open -b <bundle id> <folder>` brings the window on that folder forward (case 1). The two were never run as one: the pass was interrupted before its session step, and no session was started in the Tester's repeat | not measured end to end |
| 1. The folder is the folder the window has open | Works with `open`. VS Code 13 of 13 and Cursor 2 of 2, then 10 of 10 in each editor in the Tester's repeat | measured and repeated |
| 2. The folder is a subfolder of the window's folder | Opens a new window. The window is found only when its folder equals the path, and a folder no window has opened a new window on every attempt (the count is in the table above). The pass ran its two subfolder steps in both editors, but their results are lost | reasoned |
| 3. Two windows of the same editor are open | Works in VS Code: in the 10 of 10 run the other spike window was the last active one each time. Cursor: expected the same | VS Code measured, Cursor not measured |
| 4a. The window is on another Space | Works when the Space in front is a full-screen app's: the display switched to the editor's window, VS Code 3 of 3 and Cursor 2 of 2. A window dragged to another desktop was never tried | full screen measured, another desktop not measured |
| 4b. The window is minimized | Expected to work: VS Code restores a minimized window before it focuses it (`doFocusWindow` in `windowImpl.ts`). The pass was interrupted before its minimized step | reasoned |
| 5. The editor's shell command is not installed | Does not matter for `open`, which goes through LaunchServices. Neither `code` nor `cursor` was on PATH on the Mac where everything above was measured. The `cli` route would not need PATH either, because the command sits inside the app bundle, but it has no result | `open` measured, `cli` not measured |
| 6. The window belongs to a remote or container session | Expected to fail, or to open a new window. The hook then runs inside the container: its `cwd` is a path that does not exist on the Mac, and its environment has no `__CFBundleIdentifier`, so the session names neither a folder nor an editor. The window's folder is a `vscode-remote://` URI that holds the host folder, which the hook cannot know. The pass ran the container steps in VS Code and most of them in Cursor, but their results are lost, and `probe.sh` was never run in a container window | reasoned |

### The subfolder case: what phase 3 should do

**The command cannot be sure.** Without window names, Accessibility or the editor's own state, nothing tells the app which folder a window has open. `open -b <bundle id> <folder>` is a focus only when a window has exactly that folder. In every other case it is an "open a new window" command.

The recommendation:

1. Use only the `cwd` of the session's **first** `SessionStart`. A new integrated terminal starts in the window's folder, so this is the best guess the hook has. Never follow a later `cwd`.
2. Send `open -b <bundle id> <cwd>` only when that folder looks like a project root, for example it holds `.git`. Otherwise send `open -b <bundle id>` alone, which brings the editor forward with its last active window and opens nothing while the editor has a window.
3. For a remote or container session, the same: activate only, or no focus button.

How sure this is: **not very.** Rule 1 and rule 2 are reasoned, and the root-marker test was never tried. It fails in both directions: a window opened on a parent folder of a repository gets a second window, and a window on a folder without a marker gets the wrong window in front. `terminal.integrated.cwd` and a `cd` before the session starts break rule 1. If phase 3 wants no unwanted window at all, the only command that gives that is activate only, and it has no measured result either.

### The interrupted pass

The log is gone, so this comes from the system log, which keeps process names and times but not what the spike printed.

- What the script did: part 1 opened A and B in both editors when missing and ran the measured runs. Part 2 ran ten steps per editor: the subfolders, the `/var` spelling and the dev container. Four of the ten open a new window. Parts 3 to 7 needed the owner and were not reached.
- The pass ran for 4 min 10 s. `editor-check.swift` was started 28 times. Part 1 took 1 min 40 s, not 6 min: VS Code's `open` measured run ended after 13 s and about three attempts, VS Code's `cli` run after 36 s and about ten, and both of Cursor's ended within 5 s, in the set-up, before the first attempt. Why is not known. The script went on after a step that failed, so part 2 was offered at once.
- Part 2 ran all ten steps in VS Code in 54 s, and eight of the ten in Cursor. In each editor the two steps for the `/var` spelling ended within a second and sent no command. The system log stops 10 s after Cursor's eighth step.
- **Windows the pass opened: about ten.** VS Code started 5 new window processes, one during part 1's measured runs and four in part 2. Cursor started 5 new extension hosts in part 2, so 5 windows at most. The script was written to open A and B in part 1 when missing and four windows per editor in part 2. The four opening steps of part 1 started no window process, so A and B were most likely still open from the earlier measurement. That leaves one window more than planned in VS Code and perhaps one in Cursor, and no loop.
- Each new VS Code window started about 11 helper processes on this Mac: 56 for the 5 windows, 45 of them within one minute of part 2.
- The Mac was deep in swap before the pass: its newest swap file was number 41 when the pass began, and number 37 was from the morning. Numbers 42 to 45 were created in one minute of part 2. Then the system could not create the next one, because the disk was full, and it stopped responding 35 s later. There was no kernel panic of its own: the restart was the power button.

So the spike did not run away, and it was still the last push: it opened four windows in under a minute on a Mac that had no memory and no disk left to give. How much of the four swap files was the spike's is not known, because the system log has no memory figures per process.

What changed in the spike since: the script is removed, `measure` stops at the first new window, and `try` and `session` exit with 1 when the expected window did not come forward, so nothing can go on past a failed step without being told to.

What this means for phase 3: **an unwanted window is not only clutter.** One new editor window can start a dozen processes with the user's extensions. This is the strongest reason for the rule above, and for never sending a folder the app is not sure of in a loop or on a timer.

## Things tried that do not work

- **The folder the terminal started in.** The integrated terminal starts in the window's folder, so the shell's start-up `PWD` would name the window even after a `cd`. But macOS 27.2 shows no environment of another process, not even the user's own: `ps -E` prints the command alone, and `KERN_PROCARGS2` returns 29 bytes with no environment for a `sleep` started in the same shell.

## Ideas not tried, and their cost

- **Claude Code's IDE lock file** under `<profile>/ide/` lists the window's workspace folders. It sits in a profile folder and holds an auth token, which the rules put off limits. It exists only while the Claude Code extension is connected.
- **`code --status`** prints every window's title and folder names, the owner's included. Window titles are off limits.
- **The terminal's `VSCODE_IPC_HOOK_CLI` socket** reaches the extension host of the very window. Its protocol is internal and undocumented, and its `open` request needs a folder or a file too.
- **Opening a file inside the `cwd` with the CLI.** VS Code then picks the window whose folder contains the file (`findWindowOnFile`, which also knows multi-root workspaces). But it opens that file in an editor tab of the user's window, a visible change.
- **`--reuse-window`.** When no window has the folder, it replaces the last active window's folder. Never.

## Clean up

Close every window the spike opened by hand, in both editors, with File, Close Window: acme-web, globex-app, api, web, the acme-container windows, and any other window on one of these folders. Then `swift Spikes/editor-focus/editor-check.swift windows "$S"` must say `closed` for every noted window. Then remove the Dev Container containers by their label, the image only if the spike pulled it, and the scratch folder by its literal path:

```sh
docker ps -a --filter "label=devcontainer.local_folder=$S/acme-container" --format '{{.ID}} {{.Image}} {{.Status}}'
docker rm -f <id> …
docker images --filter 'reference=vsc-acme-container*'   # an image Dev Containers built, if any
docker image rm debian:bookworm-slim                     # only if the spike pulled it
ls "$S"; rm -r <the scratch folder>
```

After a run that was interrupted, the scratch folder and its `windows` file may be gone. Then find the containers by the folder's name, and close the spike's windows by hand: every editor window on `acme-web`, `globex-app`, `api`, `web` or `acme-container`.

```sh
docker ps -a --filter 'label=devcontainer.local_folder' --format '{{.ID}} {{.Image}} {{.Label "devcontainer.local_folder"}}' | grep 'dontburn-editor\.'
```
