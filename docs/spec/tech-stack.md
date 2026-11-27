# Tech stack

Why Swift and SwiftUI, how the app is put together, and the first cut of the data model.

Part of the product spec. First written as draft 13 of the product spec, 15 November 2026.

## Technology choice

| Need | Swift + SwiftUI | React Native (macOS + iOS) | Tauri or Electron |
| --- | --- | --- | --- |
| **Menu bar panel** | Built in | Native code needed. The status item and popover are written in Swift and host the React view. | Good |
| **Terminal scripting, hooks, file watching** | Direct | Custom native modules for each | Fine through Rust or Node |
| **Calendar via EventKit** | Direct | Native module | Plugin or OAuth only |
| **iCloud sync** | SwiftData + CloudKit | No ready path. You would write a Swift bridge or run your own backend. | Own backend |
| **iPhone app, Live Activity, widgets** | Shared code | App yes. Widgets and Live Activities are Swift anyway. | No |
| **Skills of a web developer** | New language. SwiftUI is declarative and close to React in spirit. | Familiar for the UI layer only | Familiar |
| **Moving parts** | One toolchain | Two toolchains, plus a macOS fork of React Native that trails the main one | One toolchain, Mac only |

**Decision: Swift and SwiftUI.** With React Native you would still write Swift for the menu bar, hooks, AppleScript, calendar, sync and widgets, which is most of this app, and then maintain a bridge on top. Since an AI agent will write most of the code and you will review it, one plain native codebase is the simpler thing to own.

## Architecture

**Apps**

- **Mac app**: Menu bar panel, main window, settings. History's charts use Swift Charts, a system framework, so they add no dependency
- **iPhone app**: Timer, today, history, Live Activity
- **dontburn-hook**: Tiny CLI called by Claude Code hooks, later by other agents. It reads the event on stdin, keeps only the fields of `HookEvent`, adds the `claude` process and its tty, and sends one datagram to the app's hook channel. It prints nothing and always exits 0, whether the app runs or not. It ships inside the app, at `Contents/Helpers/dontburn-hook`, the path an installed hook runs. Which build it reaches is in [../process/releases.md](../process/releases.md#everything-with-a-name-outside-the-app-follows-the-bundle-identifier)

**Shared package**

- **DontBurnCore**: Data model, timer engine, rounding rules, week and month totals (`HistoryRange`, `RangeTotals`), splitting an entry, the CSV export (`EntryExport`), what the command bar reads from typed text (`BarCommand`), the keys a global shortcut may use (`GlobalShortcut`) and what the Start at login switch shows (`LoginItemSwitch`), session states from hook events, the hook installer, the issue tracker protocol and one adapter per tracker. Pure Swift, fully unit tested.

**Mac-only services**

- **SessionMonitor**: Receives hook events, reads transcripts, and finds each session's project through the projects' folders. One adapter per agent tool and profile folder
- **HookSocket**: The hook channel, a Unix datagram socket, `Hook.socket`, in the folder named after the bundle identifier, with mode 0600. It refuses a message over 64 KB or of the wrong shape. A socket left behind by a crash or a `kill` is replaced at the next launch, and quitting removes it. A socket another running copy listens on is left alone, and the second copy runs without a channel. So does a copy whose socket path is longer than the 103 bytes a socket address holds. Both cases are logged
- **HookSetup**: Finds the Claude Code profiles for Settings, Sessions, and installs or removes the hook through `HookInstaller` in `DontBurnCore`. Each install's record and the settings file's backup go to `HookInstalls/` in the folder named after the bundle identifier, with mode 0600. The profile folders added by hand go to the defaults as `ClaudeProfileFolders`. No profile is read until the tab shows
- **AwayWatcher**: Notices time away from the Mac. It reads how long the Mac has had no input through `IdleTimeReading`, with `CGEventSource.secondsSinceLastEventType` and no permission, or the Dev build's stand-in, and takes sleep and wake from `NSWorkspace`. `AwayQuestion` keeps the waiting question in memory. The rule for each answer is `TimeAway` in `DontBurnCore`
- **HotKey**: The command bar's global shortcut, a Carbon hot key (`RegisterEventHotKey`) behind `HotKeyRegistering`, registered exclusively. It needs no permission, because it reads no other key. `CommandBarShortcut` keeps the setting and registers again on a change
- **LoginItem**: The Start at login switch, through `SMAppService.mainApp` behind `LoginItemRegistering`. The system keeps whether the app starts at login, so the app stores nothing and reads the status again each time Settings shows it. The Dev build never registers, and its stand-ins for checks keep the status in memory
- **TerminalFocus**: One adapter per terminal host
- **CalendarService**: EventKit
- **InsightFlowBridge**: Reads the current task per repo from the CLI
- **Updater**: Sparkle, for builds that other people install

**Storage**

- **SwiftData, synced**: Workspaces, projects, blocks, entries, focus presets, issue links
- **SwiftData, local only**: The folders of each project, kept in a second store for this Mac only: `Local.store`, next to `DontBurn.store` in the folder named after the bundle identifier, with its own `LocalSchemaV1` and migration plan. It is never synced, and no relationship crosses the two stores: a folder names its project by the project's identifier
- **A JSON file, this Mac only**: The agent sessions, with their terminal and tab, in `Sessions.json` next to `Local.store`. Not SwiftData, so it has no schema and no migration. A file that is missing, larger than 1 MiB or broken gives an empty list, because each session comes back with its next event. Card 47 built its loading and saving in `SessionStore`. Since card 48 the app loads it at launch and saves it after each hook event, and drops sessions whose `claude` process is gone. With the sample data the sessions stay in memory
- **Keychain**: Issue tracker tokens
- **The app's own defaults, this Mac only**: the alert switches, the last break length, the latest break with nothing running, which is never a time entry, whether the presets the app comes with were added, the Claude Code profile folders added by hand, as `ClaudeProfileFolders`, whether the app asks about time away and after how many minutes, as `away.ask` and `away.thresholdMinutes`, and the command bar's shortcut, as `commandBar.shortcutOn`, `commandBar.keyCode` and `commandBar.modifiers`

**Outside**

- **iCloud (CloudKit)**: Private database
- **Issue trackers, Jira and Trello**: REST
- **macOS Calendar**: Google accounts
- **Terminal, iTerm2**: AppleScript
- **VS Code, Cursor**: `open -b` through LaunchServices. Neither has an AppleScript dictionary, and their `code` and `cursor` commands were not tested in phase 0

## Data model, first cut

| Entity | Key fields | Synced |
| --- | --- | --- |
| **Workspace** | name, color, sort order, archived flag, default block minutes, default focus preset (empty means none), rounding step, whether breaks count, calendar | Yes |
| **Project** | name, workspace, sort order, archived flag, whether its time is tracked, optional tracker link: the tracker account and the project or board there | Yes |
| **ProjectFolder** | its own id, the project's identifier, folder path with symlinks resolved | No, this Mac only, in the local store |
| **TimeBlock** | workspace, planned start, planned minutes, state (planned, running, done, cancelled), the focus preset it started with, and its own copy of that preset's plan: focus, break and long break minutes, rounds before the long break, whether work resumes by itself after a break | Yes |
| **TimeEntry** | start, end, kind (work, break, meeting), planned minutes (set on a break, so it survives a restart), workspace, project, block, issue link, note, source (timer, manual, calendar) | Yes |
| **TimeOff** | start, end, workspace (empty means every workspace), source (calendar, manual), whether you worked anyway | Yes |
| **IssueLink** | tracker account, issue key or id, summary snapshot | Yes |
| **WorklogPush** | entries covered, seconds tracked, seconds sent after your edits, comment, the tracker's worklog id, status, sent at. Only for a tracker that keeps time | Yes |
| **FocusPreset** | name, focus minutes, break minutes, long break minutes, rounds before the long break (0 for either means no long break), whether work resumes by itself after a break. It holds no sound, because the focus-end alert is the same for every preset | Yes |
| **TrackerAccount** | tracker kind (Jira, Trello), base URL, account, Keychain reference (the token itself is not stored here) | Yes, without token |
| **AgentSession** | tool (claude, later codex), session id, profile folder, working folder, the terminal's bundle id, the `claude` process id, its tty, the iTerm2 tab id, state, last activity. Its project is worked out from the folder each time it is read | No, this Mac only, in `Sessions.json` |

CloudKit rules applied from the start: every property has a default or is optional, relationships are optional, no unique constraints, and fields are only ever added.

Card 9 built Workspace, Project, TimeBlock and TimeEntry as `SchemaV1` in `DontBurnCore`, without the fields that belong to later phases (focus preset, calendar, tracker link, issue link). Their field names are fixed from now on, because sync cannot rename them. Folder paths never enter the synced model, because they belong to one Mac. Card 10 added the planned minutes of a TimeEntry. Card 46 added ProjectFolder (`id`, `projectID`, `path`) as `LocalSchemaV1`, the local store's own schema, and left `SchemaV1` as it was. Card 47 added AgentSession outside SwiftData, so neither schema changed. Card 57 added FocusPreset, the default preset of a Workspace, and a TimeBlock's preset with its copy of the plan, as `SchemaV2`. `SchemaV1` stays exactly what v0.1.0 stores hold, and the migration plan moves a store to `SchemaV2` in one lightweight stage. The field is `focusMinutes`, not work minutes, because work is already an entry kind. At launch, a store with no presets gets 25/5 and 50/10, with fixed ids, so two Macs make the same two. Since card 58 this happens once on each Mac: its defaults remember it, so presets that were removed stay removed there. Card 58 changed no schema. No workspace is given one, so existing data runs as before. "None" is no preset, not a stored row. Card 59 changed no schema either: a question about time away lives in memory only. Neither did card 60: week and month totals, a split and the export work on the entries as they are. The other entities arrive with their phases. The rules for the model are also in `CLAUDE.md`.

- **Delete rules:** deleting a workspace deletes its projects, blocks and entries. Deleting a project or a block keeps their entries and only clears the link. Deleting a focus preset only clears it from its workspaces and blocks, and a started block keeps its copy of the plan. The app deletes one only while no workspace names it, archived ones included: the model cannot say so, because sync allows no such delete rule, so `PresetRoster` checks it.
- **The project rule:** a block or entry names a project only through `assign(_:)`, and only a time-tracked project of its own workspace.
