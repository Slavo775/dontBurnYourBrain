# Feasibility

How each feature can be built, what it depends on, and where the risks are.

Part of the product spec. First written as draft 13 of the product spec, 15 November 2026.

## Can it be done? Feature by feature

| Feature | Verdict | How | Caveats |
| --- | --- | --- | --- |
| **Menu bar app, timers, sounds, notifications** | Yes | SwiftUI `MenuBarExtra` for the status item and panel, `UserNotifications` for alerts, bundled sound files. | None. This is standard platform work. |
| **History and charts** | Yes | SwiftData for storage, Swift Charts for week and month views. | None. |
| **List Claude Code sessions** | Yes | Claude Code hooks. A small hook script reports session start, prompt, stop and "needs attention" events to the app. Each event carries the session id, the transcript file path and the working directory. Transcripts are local JSONL files, so titles and last activity can be read from disk. | The app installs hook entries into your Claude settings file. It must do this carefully and reversibly. |
| **Three Claude accounts** | Yes, with caveats | Verified on the maintainer's Mac: each account has its own Claude Code profile folder. The app watches all of them and labels sessions by profile. | The hook has to be installed once per profile. Chats in claude.ai or the desktop app have no public listing API, so only Claude Code sessions on this Mac are covered. |
| **Codex sessions** | Yes, with caveats | Codex CLI also writes local session files and supports a notify command. Same pattern as Claude. | Not in use on the maintainer's Mac yet. This adapter is built when it is first needed, and nothing else depends on it. |
| **Focus Terminal and iTerm2** | Yes | The hook script runs inside the terminal, so it can read which app and which tab it is in (`TERM_PROGRAM`, `ITERM_SESSION_ID`, the tty). The app then selects that exact tab through AppleScript. | macOS asks once for permission to control each terminal app. |
| **Focus VS Code and Cursor** | Yes, with caveats | Opening the project folder with the `code` or `cursor` command brings the right window forward. | Decided: window-level focus is enough. Selecting the exact integrated terminal tab would need a companion extension, which is not planned. |
| **Jira: pick issues, log time** | Yes | Jira Cloud REST API. Search with JQL for your issues, then post a worklog to the issue with seconds spent, start time and comment. The same API updates and deletes a worklog, so hours can be corrected after sending. Sign in per site with email and API token. | The site must have time tracking enabled. If an organization logs time through Tempo, that is a separate API. Self-hosted Jira uses a different token type. Correcting a sent worklog needs the project permission to edit your own worklogs. |
| **Google calendars from company accounts** | Yes, with caveats | Verified on the maintainer's Mac with a company Google account: once a Google account is added in macOS System Settings with Calendars switched on, its meetings land in the calendar the Mac already keeps. The app reads every calendar from there through EventKit with one permission prompt. No Google sign-in code in the app. | macOS fetches a Google account every 15 minutes by default, so a change made in the last few minutes can be missing. Out of office arrives as a timed entry and nothing is proven to mark it, so the app goes by its name, from a short list you can edit, and phase 5 checks whether macOS passes along a marker too. Another company's admin can block this route. Fallback is the Google Calendar API with OAuth, which needs a Google Cloud project and may need admin approval. |
| **Sync Mac and iPhone through Apple ID** | Yes, with caveats | SwiftData with CloudKit private database. Data lives in your own iCloud, no server to run. | Needs the paid Apple Developer Program. CloudKit restricts the data model (no unique constraints, optional relationships, additive-only changes after go-live). Mac sync has known quirks that we design around. |
| **iPhone app** | Yes | Second SwiftUI target reusing the shared package. Live Activity for the countdown. | Sessions and terminal focus stay Mac-only. The phone can show session state read-only if we sync it. |
| **insight-flow** | Yes | Verified in the insight-flow repository: `insight-flow current` prints JSON with the id, title and status of the current task, and each project has one current task. The app detects repos with `taskflow.config.json`, asks the CLI and watches `.taskflow-activity.jsonl` for changes. | insight-flow ships its own alert sounds for an idle agent and for a permission prompt, so alerts need a per-project switch to avoid doubling. |
| **Installable by other people** | Yes, with caveats | Decided: free, open source, no App Store for now. Sign the app with a Developer ID certificate, have Apple notarize it, and offer it on the project page as a download that updates itself through the Sparkle framework. iCloud sync works in such a build too, and every user keeps their data in their own iCloud, so there is still no server to run. | Needs the paid Apple Developer Program even though the app is free. Without the App Store, the iPhone app reaches other people only through a TestFlight link, where every build stops working after 90 days. |
| **Mac App Store release** | Not for this app | App Store apps must be sandboxed. A sandboxed app cannot read other tools' session files or script terminals freely. | Run it from Xcode yourself. For other people, sign and notarize it as a direct download, which is how most developer tools for the Mac are shipped. |

### How a session gets linked to its terminal

1.  You start `claude` in any terminal.
2.  The SessionStart hook runs a tiny script in that same terminal.
3.  The script sends the app: session id, folder, account, terminal app, tab identifier.
4.  Later hooks update the state: working, finished, waiting for permission.
5.  Focus button: the app tells that terminal app to select that tab.

No screen scraping, no accessibility tricks. The hook is the only moving part.

### Biggest technical risks

- **Terminal focus reliability** across four terminal hosts. Mitigation: prove it in a phase 0 spike before anything else is built on it.
- **CloudKit sync on Mac.** Mitigation: add sync late, on a stable data model, and design the model for CloudKit from day one.
- **Hook formats change** as Claude Code and Codex evolve. Mitigation: one small adapter per tool, tolerant parsing.
- **Company restrictions** on Jira tokens or calendar access. Mitigation: both integrations are optional and the app is complete without them.
- **Other people's setups** differ: other terminals, agents and Jira flavors. Mitigation: one adapter per terminal and per agent behind a common interface, added when someone needs it.

### Sources checked for this assessment

- [Claude Code hooks reference](https://code.claude.com/docs/en/hooks) (hook events and the session id, transcript path and working directory they provide)
- [Jira Cloud REST API, issue worklogs](https://developer.atlassian.com/cloud/jira/platform/rest/v3/api-group-issue-worklogs/)
- [Fixing macOS SwiftData and CloudKit sync](https://fatbobman.com/en/snippet/fix-synchronization-issues-for-macos-apps-using-core-dataswiftdata/) and [Apple forum thread on Mac sync refresh](https://developer.apple.com/forums/thread/756315)
- [React Native for macOS as a menu bar app](https://www.newline.co/@kchan/converting-a-react-native-for-macos-application-into-a-menu-bar-application--9638602d) (shows the native Swift work still required)
- [Apple, Xcode versions and requirements](https://developer.apple.com/support/xcode/)
- [insight-flow package readme](https://www.pkgstats.com/pkg:insight-flow)

The phase 0 spikes test the rows about sessions and terminal focus. Their findings go to `docs/spikes/phase-0.md`, and this file is corrected then.
