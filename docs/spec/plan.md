# Plan

The phases, from setup to a release for other people.

Part of the product spec. First written as draft 13 of the product spec, 15 November 2026.

## Stages

Estimates assume evenings and weekends with an AI agent writing most of the code and you reviewing and testing. Roughly 11 to 15 weeks to the full scope for your own use, then 2 to 3 more to make it installable by other people. The app is usable daily from the end of phase 1.

The phases run one after the other, except phases 2 and 3, which run side by side. Their cards are worked in the order of the Ready list on the board, and a card starts once the cards that block it are done. Each of the two phases ends with its own release, and the one that finishes first takes the next version.

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

Exit: you run a full working day on it. Met on 19 November 2026, the first full working day on the Release build v0.1.0 from card 17.

### Phase 2: Focus rhythm and history

Length: 1 week. Runs side by side with phase 3.

- Focus rhythm in the timer engine: presets such as 25 and 5 or 50 and 10, a workspace's default preset, planned focus intervals and breaks, and a long break after a number of rounds. A meeting inside a block is not marked by hand: it waits for the calendar in phase 5, the owner's decision on card 57
- The rhythm in the panel, the menu bar and Settings: the planned breaks as gaps in the strip, "break in 19 min", the Rhythm tab, and an alert when a focus interval ends
- Idle detection: after time away from the Mac during a block, the app asks what that time was, and changes nothing without an answer
- Week and month charts with totals per workspace and project, splitting an entry, CSV export
- Command bar on a global shortcut
- Launch at login, off by default
- A release, then a few working days on it

The right-click menu was built in phase 1. Phase 2 adds the command bar to it, and phase 3 "Focus the waiting session".

Exit: your daily copy has the rhythm, the idle question, week and month history, the command bar and launch at login, and you have used it for a few working days.

### Phase 3: Agent sessions and terminal focus

Length: 2 to 3 weeks. Runs side by side with phase 2.

- Projects get their screen in Settings: a name, the folders that belong to the project, and whether its time is tracked. Folder paths belong to one Mac and are never synced. A workspace without projects works as in phase 1
- Session states from hook events, in the shared package, with the session's project found through the projects' folders
- A fallback for a turn that ends without a `Stop`. After a denied permission the `idle_prompt` notification ends it. After an Esc no event comes at all, so the session stays "working" until its next event, a limit the owner accepted on card 47
- The hook tool hands each event to the running app, and a session never waits for it when the app is not running
- Hook installer with a clean uninstall, once per settings file even when several profiles share it through a symlink, and only into a file that comes back byte for byte from a two-space JSON round trip
- Expanded panel with the session list and state, grouped by workspace and project through the projects' folders. A session in no project's folder is listed under "Other". The list is the same with no block running, and it lists the sessions of projects whose time is not tracked
- Focus adapters: Terminal, iTerm2, VS Code, Cursor, plus ⌘1 to ⌘9 and the keyboard session switcher
- Terminal checks before every focus that the session's `claude` process still holds the tab's tty. No adapter focuses while the screen is locked
- VS Code and Cursor get the session's folder only when it is likely the window's own folder, and are only brought forward otherwise. The rule is measured before it ships, because phase 0 only reasoned it. Nothing is sent to an editor that is not running
- The app asks for Automation itself, once per terminal app, with the reason in its Info.plist. No Focus button where it is denied
- Needs-you alerts: the amber badge, the needs-you strip and a notification, also with no block running and for projects whose time is not tracked. Profile labels
- The Focus button proven from the menu bar app with live sessions, the editors' case end to end
- A release, then a week of daily use
- A spike: whether a workspace can name a Chrome profile and bring its window forward. The app can open a new window in a profile, but not bring the user's own window forward, and listing the profiles needs macOS's App Data permission for Chrome. A feature card is written only from what it finds and the owner's choice: [../spikes/chrome-profiles.md](../spikes/chrome-profiles.md)

What this phase builds on, and what is still open, is in [../spikes/phase-0.md](../spikes/phase-0.md).

Exit: you stop hunting for terminal windows. It is checked with you after a week on the release.

### Phase 4: Issue trackers

Length: 1 to 2 weeks.

- One interface for issue trackers, with one adapter per tracker. Jira and Trello are built together. Each adapter declares what it can do, such as keeping time
- A project names its tracker. A workspace has none of its own
- First find out in each organization whether Jira time is logged natively or through Tempo
- Connect trackers, tokens in Keychain
- Issue picker on blocks and entries
- Review screen with the rounding and break rules of each workspace and editable hours. Worklogs go only to a tracker that keeps time: send them, correct or remove them after sending, retry

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

The tasks of phases 0 to 3 are cards on the Trello board. [../process/tasks.md](../process/tasks.md) lists them and says when later phases get theirs.
