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

- **Mac app**: Menu bar panel, main window, settings
- **iPhone app**: Timer, today, history, Live Activity
- **dontburn-hook**: Tiny CLI called by Claude Code hooks, later by other agents

**Shared package**

- **DontBurnCore**: Data model, timer engine, rounding rules, Jira client. Pure Swift, fully unit tested.

**Mac-only services**

- **SessionMonitor**: Receives hook events, reads transcripts. One adapter per agent tool and profile folder
- **TerminalFocus**: One adapter per terminal host
- **CalendarService**: EventKit
- **InsightFlowBridge**: Reads the current task per repo from the CLI
- **Updater**: Sparkle, for builds that other people install

**Storage**

- **SwiftData, synced**: Workspaces, projects, blocks, entries, issue links
- **SwiftData, local only**: Agent sessions, terminal references
- **Keychain**: Jira tokens

**Outside**

- **iCloud (CloudKit)**: Private database
- **Jira sites**: REST
- **macOS Calendar**: Google accounts
- **Terminal, iTerm2, VS Code, Cursor**: AppleScript and CLI

## Data model, first cut

| Entity | Key fields | Synced |
| --- | --- | --- |
| **Workspace** | name, color, sort order, archived flag, default block minutes, focus preset, rounding step, whether breaks count, folder paths that belong to it, linked Jira site, calendar | Yes |
| **Project** | name, workspace, optional Jira project key | Yes |
| **TimeBlock** | workspace, planned start, planned minutes, focus preset, state (planned, running, done, cancelled) | Yes |
| **TimeEntry** | start, end, kind (work, break, meeting), workspace, project, block, issue link, note, source (timer, manual, calendar) | Yes |
| **TimeOff** | start, end, workspace (empty means every workspace), source (calendar, manual), whether you worked anyway | Yes |
| **IssueLink** | Jira site id, issue key, summary snapshot | Yes |
| **WorklogPush** | entries covered, seconds tracked, seconds sent after your edits, comment, Jira worklog id, status, sent at | Yes |
| **FocusPreset** | name, work minutes, break minutes, long break rule, sounds | Yes |
| **JiraSite** | base URL, account email, Keychain reference (the token itself is not stored here) | Yes, without token |
| **AgentSession** | tool (claude, codex), session id, account label, folder, state, last event, transcript path, terminal reference | No, this Mac only |

CloudKit rules applied from the start: every property has a default or is optional, relationships are optional, no unique constraints, and fields are only ever added.

Card 9 builds Workspace, TimeBlock and TimeEntry. The other entities arrive with their phases. The rules for the model are also in `CLAUDE.md`.
