# Plan

The phases, from setup to a release for other people.

Part of the product spec. First written as draft 13 of the product spec, 15 November 2026.

## Stages

Estimates assume evenings and weekends with an AI agent writing most of the code and you reviewing and testing. Roughly 11 to 15 weeks to the full scope for your own use, then 2 to 3 more to make it installable by other people. The app is usable daily from the end of phase 1.

### Phase 0: Setup and risk spikes

Length: 1 weekend.

- Project foundation, done before the first task: repository, Xcode project, the Trello board and the first cards
- One local check command for lint, build and tests, and the project's own agent flow
- Empty menu bar app that shows a clock
- Spike 1: a Claude hook that reports a session and focuses its tab in iTerm2 and Terminal, proven in a scratch project first and then in every profile. Every profile on the maintainer's Mac shares one settings file, so one install on that file covered them all
- Spike 2: same for VS Code and Cursor at window level. It works when the session's folder is exactly the window's folder. The main case was met in two halves, not end to end
- What the spikes found: [../spikes/phase-0.md](../spikes/phase-0.md)

Exit: you can build and run from Xcode and from the command line, and the focus trick is proven or its limits are known. The focus trick is proven for Terminal and iTerm2, with three limits: the visible jump to another Space, no focus while the screen is locked, and the process check before a Terminal tab. For VS Code and Cursor its limits are known: only an exact folder match is a focus. How the whole line was met is in [../spikes/phase-0.md](../spikes/phase-0.md#phase-0s-exit-line).

### Phase 1: Time blocks MVP

Length: 1 to 2 weeks.

- Workspaces you create and edit in Settings; start, pause, switch, extend, end
- Menu bar countdown, compact panel with quick actions and quick start
- Notifications and sounds
- Today list and simple history, manual edits

Exit: you run a full working day on it.

### Phase 2: Focus rhythm and history

Length: 1 week.

- Work, break and meeting segments, pomodoro presets
- Week and month charts, CSV export
- Command bar, right-click menu, idle detection, launch at login

### Phase 3: Agent sessions and terminal focus

Length: 2 to 3 weeks.

- Hook installer with a clean uninstall, once per settings file even when several profiles share it through a symlink, and only into a file that comes back byte for byte from a two-space JSON round trip
- Expanded panel with the session list and state, grouped by workspace through folder rules
- A fallback for a turn that ends without a `Stop`, after a denied permission or an Esc, so a session never stays "working" or "waiting"
- Focus adapters: Terminal, iTerm2, VS Code, Cursor, plus the keyboard session switcher
- Terminal checks before every focus that the session's `claude` process still holds the tab's tty. No adapter focuses while the screen is locked
- VS Code and Cursor get the session's folder only when it is likely the window's own folder, and are only brought forward otherwise. The rule is measured before it ships, because phase 0 only reasoned it. Nothing is sent to an editor that is not running
- The app asks for Automation itself, once per terminal app, with the reason in its Info.plist. No Focus button where it is denied
- Needs-you notifications, profile labels
- The Focus button proven from the menu bar app with live sessions, the editors' case end to end

What this phase builds on, and what is still open, is in [../spikes/phase-0.md](../spikes/phase-0.md).

Exit: you stop hunting for terminal windows.

### Phase 4: Jira

Length: 1 to 2 weeks.

- First find out in each organization whether time is logged natively or through Tempo
- Connect sites, tokens in Keychain
- Issue picker on blocks and entries
- Review screen with the rounding and break rules of each workspace and editable hours; send worklogs, correct or remove them after sending, retry

### Phase 5: Calendar and day plan

Length: 2 weeks.

- Read meetings through EventKit, choose which calendars count, leave out the invitations you declined
- Out of office: find the entries, mark the workspace or the whole day as off, keep reminders quiet
- Timeline for today, "free until" hint, meeting entries
- Day plan: lay out blocks around meetings, start a planned block with one click, plan against reality in history

### Phase 6: iCloud sync and iPhone

Length: 2 to 3 weeks.

- Join the Apple Developer Program, enable CloudKit
- Sync between two installs, conflict rule for the running entry
- Test sync early in a signed and notarized build, because it can work from Xcode and still fail in a distributed build. The same for the Focus button's Apple events, which phase 0 never sent from a signed, hardened build
- iPhone app: timer, today, history, Live Activity
- Install on your phone through TestFlight

### Phase 7: insight-flow and polish

Length: 1 week.

- Active insight-flow task beside sessions and as entry label
- Widgets for macOS and iOS
- A per-project switch so insight-flow and this app do not both play alerts

### Phase 8: Release for other people

Length: 2 to 3 weeks.

- First-run setup: workspaces, profile detection, hook install with consent, how to add a calendar account, permissions one at a time
- Public repository under the MIT license; releases as signed, notarized downloads that update themselves
- Adapters as they are needed: Codex once you use it, then the terminals, agents and Tempo that the first outside users ask for
- A privacy note, a README and a way to report problems
- iPhone app for other people through a TestFlight link, with a fresh build at least every 90 days

Exit: a colleague installs it from a link and is tracking time within ten minutes, without your help.

### What success looks like after a month of use

- Starting a block takes under 5 seconds
- At least 90% of working time lands in an entry without manual repair
- Focus button reaches the right terminal at least 9 times out of 10
- Daily Jira logging takes under 2 minutes

Phase 0 measured only the focus command, sent from a script: 120 of 120 per terminal app, and 10 of 10 per editor when the session's folder is exactly the window's folder. It did not measure the button in the app, with live sessions, or over a month of use. In VS Code and Cursor the line can hold only as often as a session's folder is its window's folder.

The tasks of phases 0 and 1 are cards on the Trello board. [../process/tasks.md](../process/tasks.md) says when later phases get theirs.
