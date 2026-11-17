# Spike: bring the right window forward in VS Code and Cursor

Card #7. Throwaway code that answers one question: can a command bring forward the VS Code or Cursor window that holds a given Claude Code session? Window level is enough. It is not part of the app, not in `project.yml` and not built by the check. The findings go to `docs/spikes/`.

| File | What it is |
|---|---|
| `editor-check.swift` | Runs one focus command, a measured run, or the main case from a logged session, and reads four signals after each. Notes every window that appears during an attempt by its window number, so the spike knows which windows it opened. Run it with `swift`, nothing to build |
| `hand-steps.sh` | The guided pass for one person at the Mac. Prompts each step, runs `editor-check.swift`, and appends everything to `<scratch>/hand-steps.log` |
| `probe.sh` | Runs inside a Dev Container window's terminal. Writes where that terminal runs, the names of the editor's environment variables and its parent processes to `probe-<editor>.txt` |

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

- **Focus will jump** between VS Code, Cursor and Terminal, about 150 times in all, and the screen can slide between Spaces. Keep hands off the keyboard and the mouse while a part says "hands off". The first measured run here stopped when the owner, still at work, brought another app forward.
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

`measure` makes ten attempts to A and ten to B. Before each one, the other spike window is made the editor's last active window, and the other editor's window on the same folder is put in front. So every attempt also covers two windows of one editor, and one folder open in both editors at once. `try` starts from B (or A) as the last active window, with Terminal in front.

## The guided pass

```sh
Spikes/editor-focus/hand-steps.sh "$S"        # or with a part number to start there
```

| Part | Who | What |
|---|---|---|
| 1 | Hands off, about 6 min | Opens A and B in both editors when missing. Measured runs: `open` and `cli`, VS Code and Cursor. One `app` attempt per editor |
| 2 | Hands off, about 3 min | The subfolder `api` with `open` and `web` with `cli`, the `/var` spelling of B, and the dev container: opened with `cli --folder-uri`, then the container path, the host folder and the URI |
| 3 | Owner | Starts `claude` in the integrated terminal of each editor's acme-web window. The helper reads the `SessionStart` line, picks the editor by `__CFBundleIdentifier` and focuses its `cwd` with `open` and `cli` |
| 4 | Owner | Minimizes acme-web before each focus, two per editor |
| 5 | Owner | Moves acme-web to another desktop, then the focus, and says what the screen did |
| 6 | Owner | Runs `sh probe.sh <editor>` in each Dev Container window's terminal |
| 7 | Owner | Closes every window the pass opened. The helper checks each noted window is closed |

Single steps work too, for example `swift Spikes/editor-focus/editor-check.swift try "$S" vscode open A A`.

## Results

Measured on macOS 27.2 with three displays, VS Code 1.145.0 and Cursor 3.27.22, sent from scripts started in Terminal. The owner's Terminal was in full screen on the display where most spike windows opened, so every focus from Terminal also switched that display's Space.

**PENDING: the guided pass.** Measured so far by the Developer:

| | VS Code | Cursor |
|---|---|---|
| `open`, measured run | 10 of 10 to A, then stopped at B 1 when the owner brought another app forward. Command median 0.135 s, worst 0.159 s. Signals agree median 0.306 s, worst 0.328 s, at the first reading every time | not run yet |
| `open`, from Terminal in full screen on the same display | 3 of 3 right, about 0.30 s | 2 of 2 right, 0.29 and 0.44 s |
| Opening a folder no window has | A new window, every time. Twice in Cursor it opened on a Space that was not shown, and Cursor did not stay in front | |

## Things tried that do not work

- **The folder the terminal started in.** The integrated terminal starts in the window's folder, so the shell's start-up `PWD` would name the window even after a `cd`. But macOS 27.2 shows no environment of another process, not even the user's own: `ps -E` prints the command alone, and `KERN_PROCARGS2` returns 29 bytes with no environment for a `sleep` started in the same shell.

## Ideas not tried, and their cost

- **Claude Code's IDE lock file** under `<profile>/ide/` lists the window's workspace folders. It sits in a profile folder and holds an auth token, which the rules put off limits. It exists only while the Claude Code extension is connected.
- **`code --status`** prints every window's title and folder names, the owner's included. Window titles are off limits.
- **The terminal's `VSCODE_IPC_HOOK_CLI` socket** reaches the extension host of the very window. Its protocol is internal and undocumented, and its `open` request needs a folder or a file too.
- **Opening a file inside the `cwd` with the CLI.** VS Code then picks the window whose folder contains the file (`findWindowOnFile`, which also knows multi-root workspaces). But it opens that file in an editor tab of the user's window, a visible change.
- **`--reuse-window`.** When no window has the folder, it replaces the last active window's folder. Never.

## Clean up

After part 7, every noted window says `closed`. Then remove the Dev Container containers by their label, the image only if the spike pulled it, and the scratch folder by its literal path:

```sh
docker ps -a --filter "label=devcontainer.local_folder=$S/acme-container" --format '{{.ID}} {{.Image}} {{.Status}}'
docker rm -f <id> …
docker images --filter 'reference=vsc-acme-container*'   # an image Dev Containers built, if any
docker image rm debian:bookworm-slim                     # only if the spike pulled it
ls "$S"; rm -r <the scratch folder>
```
