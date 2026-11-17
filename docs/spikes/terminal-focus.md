# Spike: bring the exact terminal tab forward

Card #6, phase 0. Whether a command can bring forward the exact terminal tab that holds a given session, in iTerm2 and in Terminal, reliably enough to build the Focus button on.

Tested on macOS 27.2 with three displays, iTerm2 3.7.7 and Terminal 2.15. Each app had one spike window with two plain shell tabs, A and B. The Developer and the Tester each ran the measured run in two rounds and got the same picture. The spike's code and the steps to repeat it are in [Spikes/terminal-focus/README.md](../../Spikes/terminal-focus/README.md).

## The answers

1. **Can a command bring the exact tab forward?** Yes, in both apps. The right tab came forward 120 times out of 120 in iTerm2 and 120 out of 120 in Terminal. The card asked for 9 out of 10.
2. **Which identifier.** iTerm2: the session's `unique ID`, the UUID after the colon in `ITERM_SESSION_ID`. Terminal: the tab's tty, trusted only while the session's `claude` process still holds it.
3. **How fast.** The focus command takes about 0.28 seconds. The tab was in front at the first check every time, about 0.45 seconds after the command started. A minimized window takes about 0.8 seconds, because of the Dock animation.
4. **Awkward cases.** A minimized or hidden window works. A window on another Space or in full screen works with a visible jump. A tab that no longer exists changes nothing.
5. **Permissions.** No Accessibility and no Screen Recording. macOS asks once per terminal app for permission to control it, and that permission belongs to whatever sends the commands. Here it was Terminal, so the app will have to ask again for itself in phase 3.

## The handle for each app

The handles come from card #5, [claude-hook.md](claude-hook.md), and this spike confirmed them.

**iTerm2: the session's `unique ID`.**

- It is the UUID after the colon in `ITERM_SESSION_ID`, which looks like `w<n>t<n>p<n>:<UUID>`.
- It kept matching for over two hours, through minimize, hide, a move to another Space and back, and full screen in and out.
- A UUID is never given to another session. A closed session simply stops matching.
- The `w<n>t<n>p<n>` prefix only says where the session was when it opened, so the command ignores it.
- Every right attempt compared the UUID taken from `ITERM_SESSION_ID` with iTerm2's `unique ID of current session`. So the 120 right attempts also confirm that the two are the same value.

**Terminal: the tab's tty.**

- It is the only per-tab id that both the hook and AppleScript can see. AppleScript doesn't show `TERM_SESSION_ID`.
- It is stable while the tab lives, but **reused at once** after the tab closes.
- So before it focuses, the app must confirm that the session's `claude` pid still holds that tty. The spike does it with `ps -o tty= -p <pid>`. The app can use one `sysctl` call (`KERN_PROC_PID`, then `e_tdev`). A pid that has exited means "don't focus".
- iTerm2 needs no such check.

## The focus commands

`focus-iterm2.applescript` takes a unique ID and `focus-terminal.applescript` takes a tty. Each one:

1. Finds the tab by its handle. It reads only the unique ID or the tty of other tabs, never a name, a title or what a tab shows.
2. Un-minimizes the window when needed.
3. iTerm2: selects the window, the tab and the session. Terminal: selects the tab and sets its window's `index` to 1.
4. Activates the app.

When no tab matches, it changes nothing and exits 1.

**How Terminal 2.15 sees tabs:**

- Each native tab is an AppleScript window of its own, with one tab in it. The tabs share a frame and a tab bar, and only the selected one is on screen.
- So focusing a Terminal tab means bringing that tab's own window to the front. `set selected of tab` alone isn't enough.
- Terminal can open a tab by script, with `do script in new tab … next to <tab>`.
- In both apps, the AppleScript window `id` equals the window server's window number.

## How an attempt was counted

The owner decided how to count: not by eye, with no screenshots, no Screen Recording and no Accessibility. An attempt counts as right only when three independent signals agree:

1. LaunchServices (`lsappinfo front`) says the terminal is the frontmost app.
2. The terminal's AppleScript says it is frontmost, and its front window's selected tab or current session holds the target handle.
3. The topmost normal window over the target window's spot, from `CGWindowListCopyWindowInfo`, belongs to the terminal and is AppleScript's front window.

In Terminal a tab is a window, so signal 3 checks the tab too. **In iTerm2, which tab shows inside the window rests on iTerm2's own `current session` alone.** The window server sees only the window.

Before each attempt, the other spike tab was selected and the other terminal app was put in front. That is how the Focus button will be used: the user clicks the menu bar while working elsewhere. From round 2 on, the helper checks that starting state and prints it on every line.

## Measured runs

Ten attempts to tab A and ten to tab B per pass.

| Pass | iTerm2 | Terminal |
|---|---|---|
| Developer, round 1, two passes | 20/20, 20/20 | 20/20, 20/20 |
| Tester, round 1, two passes | 20/20, 20/20 | 20/20, 20/20 |
| Developer, round 2 | 20/20 | 20/20 |
| Tester, round 2, the final code | 20/20 | 20/20 |
| **Total** | **120/120** | **120/120** |

All three signals agreed at the first reading every time.

**Timing, from the Tester's pass on the final code.** The other passes were in the same range.

| | Focus command, median / worst | Signals agree, median / worst |
|---|---|---|
| iTerm2 | 0.277 s / 0.286 s | 0.455 s / 0.467 s |
| Terminal | 0.273 s / 0.287 s | 0.449 s / 0.461 s |

- Across all runs the focus median was 0.20 to 0.28 seconds. Terminal's focus time sits at two levels, about 0.20 and about 0.265 seconds.
- The focus time is the wall time of `osascript`. Its start-up costs about 0.04 seconds, so most of the time is Apple Events.
- "Signals agree" includes one reading of the signals, which takes about 0.16 seconds.

## Awkward cases

| Case | iTerm2 | Terminal |
|---|---|---|
| Minimized, by script (`miniaturized`, in both dictionaries) | **Works**, 3 of 3 in each run. The Dock's restore animation makes it 0.81 to 0.88 s | **Works**, 3 of 3. 0.80 to 0.83 s |
| Hidden: the owner pressed Cmd-H, then the focus command ran | **Works.** iTerm2 came back with the tab | **Works.** Terminal came back after the 5-second delay with the tab, the owner's own Terminal windows included |
| Another Space, judged by the owner by eye | **Works with a visible jump.** The screen slid to the window's Desktop. The window was not pulled over | The same |
| Full screen, judged by the owner by eye | **Works with a visible jump.** The view slid to the window's full-screen space | The same |
| The tab no longer exists: a random UUID, or `/dev/ttys999` that no tab holds | **Changes nothing.** Exit 1 after about 0.20 s, 3 of 3 per run | The same |

- **The Space setting.** "When switching to an application, switch to a Space with open windows for the application" (`com.apple.dock workspaces-auto-swoosh`) was absent, which means on. The Space and full-screen results were taken with it on. It was read, never changed.
- **Hiding by script doesn't work.** `NSRunningApplication.hide()` returns false for another app when called from a command-line process, so hidden became a hand step.

## What `activate` brings forward

After each run, no other app's window covered any on-screen window of the terminal: 2 of 2 in iTerm2, and 3 of 3 in Terminal, the owner's own window included. This **suggests** that `activate` brings every window of the app forward, not only the chosen one. It **does not prove it.** It was counted only after the run, and with three displays a window can be uncovered without having been raised. The target window was always on top.

## Permissions

- No prompt appeared, and no Accessibility or Screen Recording permission was used.
- **macOS asks once per terminal app for permission to control it, and the permission belongs to the sender.** When the command runs from a script, that is whatever runs the script, not this app. Every Apple Event here came from `osascript` or the Swift helper started from Claude Code in Terminal, so macOS counted them as Terminal's. Terminal controlling Terminal needs no prompt, and Terminal controlling iTerm2 was granted in card #5.
- **In phase 3 the app sends the events itself.** So macOS asks once per terminal app for the app, and again for the Dev build, which is a separate app.
- `activate` worked when sent from a background process. It still has to be checked from the menu bar app.

## A locked screen

While the screen is locked, `activate` blocks for about 2.1 seconds, the login window stays in front, and nothing comes forward. Round 1 lost about an hour to this. The helper now refuses to run while the screen is locked. The app should not try to focus while the screen is locked.

## Several displays

The test Mac has three displays. Midway through, an app parked windows outside every display, and they topped the window server's global list. So "the tab is in front" has to mean "nothing covers the target window", not "the target is first in the global window list".

## Safety work from the review

- The first review rejected the helper. It trusted a recorded Terminal tty without checking the pid. With a stale folder, it could have raised or minimized a tab the spike didn't open.
- Round 2 fixed it. Before it touches any tab, the helper now refuses a stale handle, a starting state it didn't reach, and a window that holds more than the spike's two tabs.
- The lesson for the app is the tty point above: check the pid before every focus.
- The spike sets each tab's title by writing an escape sequence from inside that tab. The app has no reason to write to a tty, and it must not: a reused tty would send it to someone else's tab.
- `open-tabs.sh` types its start command, with Return, into the Terminal tabs it opens, through `do script`. In iTerm2 the start command is the new session's command, so nothing is typed.

## Other terminals: worth an adapter or not

Not tested, only read up on.

| Terminal | How to focus a tab | Verdict |
|---|---|---|
| Ghostty 1.3 and later | An AppleScript dictionary: `focus` a terminal by `id`, `select tab`. But no tty or environment variable ties a tab to that `id`, only `working directory` | An adapter once that mapping exists |
| WezTerm | `wezterm cli activate-pane --pane-id $WEZTERM_PANE`, then activate the app | Worth an adapter |
| kitty | `kitty @ focus-window --match id:$KITTY_WINDOW_ID`, only when remote control is enabled | Worth an adapter |
| tmux and zellij | `tmux select-window` or `select-pane -t $TMUX_PANE`, and `zellij action go-to-tab` | A layer on top of the outer terminal's adapter |
| Alacritty | No tabs and no focus interface | No |
| Warp | No AppleScript dictionary and no tab-selection API | No |

Sources: [Ghostty's AppleScript docs](https://ghostty.org/docs/features/applescript) and [Automating 4 macOS terminals for Claude Code](https://dev.to/thinkerjack/automating-4-macos-terminals-for-claude-code-applescript-ghosttys-e-trap-and-warps-missing-3nk1).

## Gaps and what went wrong

**Gaps the app has to live with:**

- A window on another Space or in full screen comes forward with a visible jump. That was seen with the Space setting above on. With it off, it was not tried.
- `activate` probably raises every window of the terminal, not only the target.
- A Terminal tty needs the pid check before every focus.

**What went wrong during the spike:**

1. A locked screen made `activate` do nothing, and round 1 lost about an hour to it.
2. The window server signal first took the topmost window of all. A window another app parked outside every display then made every attempt look wrong. The signal was changed to the topmost window over the target's spot.
3. Hiding another app by script failed, so hidden became a hand step.
4. The first review rejected the helper over the stale tty. Round 2 fixed it.

## What was not done

- Hidden, another Space and full screen by script. They need hands or a permission the card rules out.
- Another Space with the Space setting off.
- The focus sent from the real menu bar app, or from a signed or hardened build.
- A real Claude Code session in the tab. Plain shell tabs were used, because the handle belongs to the tab, and card #5 proved the hook's handle equals AppleScript's.
- A split pane in iTerm2. The command selects the session inside the tab, but no split tab was tried.
- Proof that `activate` raises every window.
- VS Code and Cursor, which are card #7, and other terminals, which are only listed above.

## For card #8

Card #8 writes `docs/spikes/phase-0.md` across all the spikes and corrects the spec. What this spike says about the spec:

**[docs/spec/feasibility.md](../spec/feasibility.md), "Focus Terminal and iTerm2":**

- Verdict "Yes". **Confirmed.** 120 of 120 per app.
- "The hook script runs inside the terminal, so it can read which app and which tab it is in (`TERM_PROGRAM`, `ITERM_SESSION_ID`, the tty)." **Confirmed**, with card #5's correction: the tty is the one of the `claude` process. iTerm2's handle is the UUID after the colon. Terminal's handle is the tty.
- "The app then selects that exact tab through AppleScript." **Confirmed, with a correction for Terminal.** In Terminal 2.15 each tab is its own AppleScript window. The app brings that window to the front with `index` 1, after checking that the `claude` pid still holds the tty. Then it activates the app.
- Caveat "macOS asks once for permission to control each terminal app." **Confirmed, and incomplete.** The permission belongs to the app that sends the events. The Dev build asks on its own. The caveat should also name the visible jump for another Space or full screen, and say that nothing comes forward while the screen is locked.

**"How a session gets linked to its terminal":**

- Step 5, "Focus button: the app tells that terminal app to select that tab." **Confirmed**, with the Terminal correction above and the pid check before it.
- "No screen scraping, no accessibility tricks." **Confirmed.** Neither Accessibility nor Screen Recording was needed.

**"Biggest technical risks", "Terminal focus reliability across four terminal hosts":** **Retired for Terminal and iTerm2.** What remains: the permission from the app itself, the focus from a signed and hardened build, and VS Code and Cursor, which are card #7.

**[docs/spec/plan.md](../spec/plan.md):**

- "Focus button reaches the right terminal at least 9 times out of 10." **Confirmed for the focus command.** 120 of 120 per app. **Not tested** from the menu bar app, with real sessions, or over a month of use, which is what the line measures.
- Phase 0, "Spike 1: … focuses its tab in iTerm2 and Terminal." **Confirmed.** The exit, "the focus trick is proven or its limits are known", holds for both apps. The limits are the jump, the locked screen and the pid check.

**[docs/spec/decisions.md](../spec/decisions.md):**

- Row "Release details", adapters built first for iTerm2 and Terminal. **Confirmed.** Both can be built.
- Row "Audience", adapters for more terminals follow. The table of other terminals above says which are worth one.
- Row "Every part works alone". A tab that no longer exists changes nothing. **Not tested:** what the app does when the user denies the Automation permission. Under this row, the Focus button should then be left out.
- The assumption "A hook can tell which terminal tab it runs in, on all four terminal hosts". Nothing new for VS Code and Cursor. For iTerm2, all 120 attempts confirmed again that the UUID equals the session's `unique ID`.

**[docs/spec/dev-setup.md](../spec/dev-setup.md), "Automation, once per terminal app, to select the right tab":** **Confirmed.** It should add that the Dev and the Release build each ask, because each is its own app.

**For phase 3's code:**

- Check what a hardened, signed app needs to send Apple Events: the `NSAppleEventsUsageDescription` text in its Info.plist, and the automation entitlement. **Not tested here.**
- Don't focus while the screen is locked.
- `focus-check.swift` runs in Swift 5 mode, through `swift file.swift`. In Swift 6 mode its top-level `let`s become main-actor isolated and it doesn't compile. Fine for a spike, but don't lift it into the app as it is.

**Still open:**

- The focus sent from the menu bar app, from a signed build, and with Automation denied.
- Whether `activate` raises every window of the terminal.
- Another Space with the Space setting off.
- A split pane in iTerm2.
