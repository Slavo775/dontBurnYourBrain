# Spike: bring the exact terminal tab forward

Card #6. Throwaway code that answers one question: can a command bring forward the exact tab that holds a session, in iTerm2 and in Terminal, at least 9 times out of 10? It is not part of the app, not in `project.yml` and not built by the check. The findings go to `docs/spikes/`.

| File | What it is |
|---|---|
| `focus-iterm2.applescript` | The focus command for iTerm2. Takes the session's unique ID (the UUID after the colon in `ITERM_SESSION_ID`, or the whole value), finds that session, un-minimizes its window when needed, selects the window, the tab and the session, and activates iTerm2 |
| `focus-terminal.applescript` | The focus command for Terminal. Takes the tab's tty (`/dev/ttysNNN` or `ttysNNN`), finds the tab, un-minimizes its window when needed, brings it to the front and activates Terminal |
| `open-tabs.sh` | Opens one spike window with two tabs, A and B, in iTerm2 or Terminal. Each tab starts `start-tab.sh`, and the handles it wrote are checked against the terminal's own AppleScript |
| `start-tab.sh` | Runs inside a spike tab. Writes the tab's `tty`, its shell's pid and `ITERM_SESSION_ID`, as a hook in that tab would see them, sets the tab's title, then leaves a plain shell (`bash --noprofile --norc`) in the tab |
| `focus-check.swift` | Runs the measured run, the scripted awkward cases, and one focus for a hand step, and reads the three signals after each. Run it with `swift`, nothing to build |

Run either focus command on its own with `osascript Spikes/terminal-focus/focus-iterm2.applescript <UUID>` or `osascript Spikes/terminal-focus/focus-terminal.applescript /dev/ttysNNN`. Both read only the tty or the unique ID of other tabs, never a name, a title or what a tab shows. When no tab matches, they change nothing and exit with status 1 and the message `no Terminal tab has the tty …` or `no iTerm2 session has the unique ID …`.

## Before a run

- **Focus will jump.** A measured run switches between iTerm2 and Terminal about 60 times per app, in about 20 seconds. Tell the owner first, and keep hands off the keyboard and the mouse while it runs.
- **Unlock the screen, and keep it unlocked.** While it is locked, the login window is the frontmost app, and `activate` waits about 2 seconds and does nothing. `focus-check.swift` refuses to run then. `caffeinate -d -t 900` keeps the display awake for 15 minutes. Note its pid and stop only that one.
- **Permissions.** macOS asks once per terminal app whether the sender may control it. The sender is the app the script runs in: run from Terminal, Terminal controls Terminal without a prompt, and iTerm2 needs Terminal's permission once. The owner answers a prompt. An `osascript` that fails with −1712 usually means a prompt or dialog is open: retry once, then stop.
- **No Accessibility and no Screen Recording.** Nothing here needs either. The window server's list is read without window names.

## Set up

From the repository root, in one shell:

```sh
DIR=$(mktemp -d -t dontburn-focus)
Spikes/terminal-focus/open-tabs.sh iterm2 "$DIR"
Spikes/terminal-focus/open-tabs.sh terminal "$DIR"
```

This opens a new iTerm2 window with the tabs `dontburn-spike iTerm2 A` and `dontburn-spike iTerm2 B`, and a new Terminal window with the tabs `dontburn-spike Terminal A` and `dontburn-spike Terminal B`. Each line it prints must show that AppleScript finds the handle the tab wrote:

```
iterm2-A: ITERM_SESSION_ID w…:XXXXXXXX-…, tty /dev/ttysNNN. AppleScript's tty for that unique ID: /dev/ttysNNN
terminal-A: tty /dev/ttysNNN, held by 1 Terminal tab(s) by AppleScript
```

`$DIR/iterm2-A`, `$DIR/terminal-A` and the B files hold the handles. To reuse spike windows that are already open, set `DIR` to the folder that holds their files instead. `focus-check.swift` refuses a stale folder before it touches any tab. In Terminal, the shell pid recorded with each tty must still hold that tty, because a tty goes to the next tab once its tab closes. In both apps, AppleScript must still find tabs A and B.

Two things about the windows:

- **Terminal 2.15 opens a tab by script** with `do script in new tab … next to <tab>`. No Cmd-T is needed.
- **In Terminal every tab is an AppleScript window of its own**, with one tab in it. The two Terminal spike tabs share one window frame and a tab bar, but AppleScript lists two windows, and only the selected one is on screen. So bringing a Terminal tab forward means bringing its own AppleScript window to the front. In iTerm2, tabs are inside one AppleScript window.

## How an attempt is counted

After each focus command, `focus-check.swift` reads three independent signals, again and again for up to 3 seconds. The attempt is right only when all three agree:

1. **The frontmost app**, from LaunchServices (`lsappinfo front`), is the terminal.
2. **The terminal's AppleScript** says it is frontmost, and the selected tab of its front window holds the target handle. In Terminal a tab is a window of its own, so signal 3 checks the tab too. In iTerm2 the window server sees only the window, so which tab shows inside it rests on iTerm2's own `current session` alone.
3. **The window server's order** (`CGWindowListCopyWindowInfo`, on-screen windows only): the topmost normal window (layer 0) over the front window's spot belongs to the terminal, and its window number is the front window's AppleScript `id`. Both apps use the window server's number as their AppleScript window `id`, so the two can be matched. It is the topmost window over that spot, not the topmost window of all: with several displays, a window on another display, or a window an app parks outside every display, can be higher in the list without covering anything.

Before each attempt the other spike tab is selected and the other terminal app is put in front, because the Focus button will be clicked while the user works elsewhere. The run stops when that starting state isn't reached within 3 seconds, and every line prints it as `from=`. Each line also prints which signal said what, with tabs named A, B or other, never a handle:

```
A 1/10 from=terminal,tab B iterm2 → A: RIGHT exit=0 focus=0.268s agree=0.438s readings=1 front=iterm2 script=frontmost,tab A,window spike server=iterm2,window same
```

`focus` is the wall time of the focus command, `osascript` included. `agree` runs from the start of the focus command to the end of the first reading at which all three signals agreed. One reading takes about 0.16 seconds, so `readings=1` means the tab was already in front when the command returned.

## The measured run

```sh
swift Spikes/terminal-focus/focus-check.swift measure iterm2 "$DIR"
swift Spikes/terminal-focus/focus-check.swift measure terminal "$DIR"
```

Ten attempts to tab A and ten to tab B per app, each from the other tab and from the other app. The last lines give the counts, the median and worst timings, and an `order:` line: how many of the terminal's on-screen windows no window of another app covers, even in part, after the last attempt.

## The awkward cases

Scripted, three attempts each:

```sh
swift Spikes/terminal-focus/focus-check.swift case iterm2 minimized "$DIR"
swift Spikes/terminal-focus/focus-check.swift case iterm2 gone "$DIR"
swift Spikes/terminal-focus/focus-check.swift case terminal minimized "$DIR"
swift Spikes/terminal-focus/focus-check.swift case terminal gone "$DIR"
```

- `minimized` selects tab B, minimizes the spike window by AppleScript (`miniaturized`, in both dictionaries), puts the other app in front, and focuses tab A. Minimizing a window takes all of its tabs along, so it first checks that the spike window holds only tabs A and B. In iTerm2 the window must have two tabs. In Terminal exactly two AppleScript windows, A and B, must share the spike window's bounds. That guards against a setting such as "Prefer tabs: Always" having put the spike tabs into a window with other tabs. Never change System Settings to test it.
- `gone` focuses a handle no tab holds (`/dev/ttys999` in Terminal, a random UUID in iTerm2) and compares the three signals before and after. In Terminal it first checks that no tab holds `/dev/ttys999`. No tab is closed for it.

By hand, one person at the Mac. Each step runs `swift Spikes/terminal-focus/focus-check.swift focus <app> A "$DIR" 5`. It waits 5 seconds, so you can click a window of an app that is neither Terminal nor iTerm2 (an empty spot on the desktop works), then focuses tab A and prints one result line and the `order:` line. Look at what the screen does, and judge "jump" or "no jump".

1. **Another Space.** Open Mission Control (Ctrl-Up). If the top bar shows one desktop, click + to add Desktop 2. Drag the spike window onto Desktop 2 and click Desktop 1. Run the command for that app. Afterwards go back to Desktop 1 (Ctrl-Left). Do it for the iTerm2 and the Terminal spike window, then drag both back onto Desktop 1 in Mission Control.
2. **Full screen.** Click the spike window, press Ctrl-Cmd-F, go back to Desktop 1 with Ctrl-Left, and run the command for that app. Afterwards press Ctrl-Cmd-F in the spike window to leave full screen. Once per app.
3. **Hidden.** iTerm2: click the spike window, press Cmd-H (it hides every iTerm2 window), click back into your own terminal and run the command without the 5. Terminal: run the command with the 5, then bring Terminal to the front and press Cmd-H at once. It hides every Terminal window, your own too, and the focus should bring Terminal back. Hiding is a hand step, because `NSRunningApplication.hide()` returns false for another app when called from here, and every other way needs a new permission.

## The tty is reused

A tty name goes to the next tab that opens once its tab closes. So a stored tty is only trusted while the process that held it, `claude` in the app and the shell here, still holds it:

```sh
PID=$(sed -n 's/^pid=//p' "$DIR/terminal-A"); TTY=$(sed -n 's/^tty=//p' "$DIR/terminal-A")
[ "/dev/$(ps -o tty= -p "$PID" | tr -d ' ')" = "$TTY" ] && echo "still holds it" || echo "gone, do not focus"
```

A pid that has exited gives an empty tty, so the check says "gone". iTerm2's unique ID is a UUID that is never handed to another session, so it needs no such check.

## Results

Measured on macOS 27.2 with three displays, iTerm2 3.7.7 and Terminal 2.15, sent from scripts started in Terminal. Two spike sessions in two tabs of one window per app.

The measured run was done three times per app, with 20 of 20 each time:

1. The first time, the window server signal took the topmost window of all. Then a window that another app parks outside every display came up and made every attempt look wrong, so the signal changed to the topmost window over the target's spot.
2. The second run used that signal.
3. The third run used the code in this folder, which adds the checks on stale handles and on the starting state.

The table gives the third run for the measured run and the gone case, and the second run for the minimized case, which was not repeated.

| | iTerm2 | Terminal |
|---|---|---|
| Measured run: right tab, all three signals agree | **20 of 20**: 10 of 10 to A, 10 of 10 to B | **20 of 20**: 10 of 10 to A, 10 of 10 to B |
| Focus command, wall time | median 0.265 s, worst 0.269 s | median 0.264 s, worst 0.334 s |
| Signals agree | median 0.431 s, worst 0.440 s. At the first reading every time | median 0.424 s, worst 0.491 s. At the first reading every time |
| Minimized | **Works**, 3 of 3. The window comes back from the Dock with the restore animation, which the command waits for: median 0.85 s, worst 0.87 s | **Works**, 3 of 3. The same: median 0.81 s, worst 0.82 s |
| Hidden (owner, by hand) | **Works.** iTerm2 came back with tab A | **Works.** Terminal came back by itself after the 5 seconds, with tab A |
| Another Space (owner, by eye) | **Works with a visible jump.** The screen slid to Desktop 2 with tab A selected. The window was not pulled over | **Works with a visible jump.** The same |
| Full screen (owner, by eye) | **Works with a visible jump.** The view slid to the window's full-screen space with tab A | **Works with a visible jump.** The same |
| The tab no longer exists | **Changes nothing**, 3 of 3. Exit 1, `no iTerm2 session has the unique ID …`, after 0.20 s | **Changes nothing**, 3 of 3. Exit 1, `no Terminal tab has the tty …`, after 0.20 s |
| After the run, which on-screen windows of the app no other app's window covers | 2 of 2, the target on top | 3 of 3, the target on top |

- The last row suggests that `activate` brings every window of the app forward, not only the target, because the other app was in front just before. It is not proven: `order:` counts only after the run, and with three displays a window can be uncovered without having been raised. Comparing the covered windows before and after would settle it.
- `osascript` itself starts in about 0.04 s, so most of a focus is Apple Events.
- "When switching to an application, switch to a Space with open windows for the application" was on: `defaults read com.apple.dock workspaces-auto-swoosh` finds no key, which means on. The Space and full-screen results depend on it.
- No permission prompt came up. Every Apple Event was sent by `osascript` or `focus-check.swift`, both started from Terminal, so macOS counted them as Terminal's.
- While the screen was locked, `activate` took 2.1 s, the login window stayed in front, and nothing came forward.

## Clean up

The spike windows are left open for the Tester. To close them, close their tabs with Cmd-W (each runs a plain `bash`, so nothing asks), then look at the folder and remove it by its literal path: `ls <folder>`, then `rm -r <folder>`.
