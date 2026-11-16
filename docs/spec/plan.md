# Plan

The phases, from setup to a release for other people.

Part of the product spec. First written as draft 13 of the product spec, 15 November 2026.

## Stages

Estimates assume evenings and weekends with an AI agent writing most of the code and you reviewing and testing. Roughly 11 to 14 weeks to the full scope for your own use, then 2 to 3 more to make it installable by other people. The app is usable daily from the end of phase 1.

### Phase 0: Setup and risk spikes

Length: 1 weekend.

- Project foundation, done before the first task: repository, Xcode project, the Trello board and the first cards
- One local check command for lint, build and tests, and the project's own agent flow
- Empty menu bar app that shows a clock
- Spike 1: a Claude hook that reports a session and focuses its tab in iTerm2 and Terminal, proven in a scratch project first and then in every profile
- Spike 2: same for VS Code and Cursor at window level

Exit: you can build and run from Xcode and from the command line, and the focus trick is proven or its limits are known.

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

Length: 2 weeks.

- Hook installer with a clean uninstall
- Expanded panel with the session list and state, grouped by workspace through folder rules
- Focus adapters: Terminal, iTerm2, VS Code, Cursor, plus the keyboard session switcher
- Needs-you notifications, profile labels

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
- Test sync early in a signed and notarized build, because it can work from Xcode and still fail in a distributed build
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

The tasks of phases 0 and 1 are cards on the Trello board. [../process/tasks.md](../process/tasks.md) says when later phases get theirs.
