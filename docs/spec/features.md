# Features

Every feature with its priority and phase, a normal day with the app, and the rules about time.

Part of the product spec. First written as draft 13 of the product spec, 15 November 2026.

## Features and priorities

Must = needed for the app to be worth opening daily. Should = planned, later phase. Could = only if cheap.

| Area | What it does | Priority | Phase |
| --- | --- | --- | --- |
| **Workspaces** | Any number of workspaces that you create, rename, recolor, reorder and archive yourself. Each has a color, a default block length and rhythm, its own rounding and break rules, the folders that belong to it, and optionally a Jira site and a calendar. Acme, Globex and Personal are sample data throughout this spec. | Must | 1 |
| **Projects** | Each workspace holds its own projects, with a name, an order and an archive. A project's time can be switched off from tracking, for things you do but do not log. A block or entry names only a tracked project of its own workspace. The model arrives in phase 1, the screens to manage projects and their folders in phase 3, and the link to an issue tracker in phase 4. | Must | 1 to 4 |
| **Time blocks** | "Next 2 hours: Acme." Countdown in the menu bar, pause, extend, switch workspace, end early. Each block is saved as time entries. | Must | 1 |
| **Alerts** | System notification and sound when a block, focus interval or break ends. Optional warning 5 minutes before. Selectable sounds. | Must | 1 |
| **Menu bar overview** | Menu bar shows workspace and remaining time. Click opens a compact panel with the current block and four quick actions. One more step expands it to sessions, the plan for today and totals. | Must | 1 |
| **Quick functions** | Quick-start presets, a right-click menu on the menu bar item, and a command bar on a global shortcut for starting a block, pausing, taking a break and jumping to the waiting session. | Should | 1 to 2 |
| **History** | Day, week and month views. Totals per workspace, project and issue. Edit or split entries. CSV export. | Must | 1 to 2 |
| **Focus rhythm** | Split a block into work, break and meeting segments. Pomodoro presets (25/5, 50/10) or custom. Breaks are recorded as their own kind, and each workspace decides whether they count toward the logged hours. | Should | 2 |
| **Agent sessions** | Live list of Claude Code sessions on this Mac: project folder, profile, state (working, waiting for you, idle), last activity. A session belongs to a workspace through its folder. Other agents, Codex first, plug in later as adapters. | Must | 3 |
| **Focus terminal** | One click brings the terminal that holds a session to the front: the exact tab in Terminal and iTerm2, the right window in VS Code and Cursor. A keyboard switcher cycles through sessions. | Must | 3 |
| **Needs-you alerts** | Notification when an agent is waiting for permission or input, with a button that focuses its terminal. | Should | 3 |
| **Multiple Claude accounts** | Each Claude Code profile folder is one account. For example personal, client and work. Every session carries its profile as a label, and more profiles can be added by path. | Should | 3 |
| **Jira issues** | Connect several Jira sites. Pick an issue for the current block from "assigned to me" or by key. Time entries carry the issue. | Should | 4 |
| **Jira worklogs** | Review screen: entries grouped per issue and rounded to your rule. Before sending you can change the hours, the comment and the issue, or leave a row out. After sending you can still change the hours or remove the worklog, and the app updates Jira. | Should | 4 |
| **Calendar** | Meetings from company Google accounts shown on today's timeline. "Free until 14:00" hint when you start a block. Meetings can become meeting entries automatically. Every meeting counts unless you declined it. An Out of office entry is not a meeting: it marks the workspace as off for the day, and the app shows it and stays quiet. | Should | 5 |
| **Day plan** | Lay out the whole day as blocks around your meetings, in the morning or the evening before. The plan shows in the panel, a planned block starts with one click when its time comes, and history compares plan with reality. | Should | 5 |
| **iCloud sync** | Workspaces, blocks, entries and issue links sync between your devices through your Apple ID. | Should | 6 |
| **iPhone app** | Start, stop and switch blocks, see today and history, Live Activity with the countdown on the Lock Screen. | Should | 6 |
| **First-run setup** | A short guided start for a new user: create workspaces, find the Claude Code profiles, install the hook with consent, show how to add a calendar account to the Mac, and ask for permissions one at a time with the reason for each. | Should | 8 |
| **Install and updates** | Free and open source. A signed and notarized download from the project page that updates itself, so other people can use the app without Xcode. | Should | 8 |
| **insight-flow** | For repos that use insight-flow, show the active task next to the session and offer it as the label for the time entry. | Could | 7 |
| **Desktop widget** | macOS and iOS widget with the current block and today's totals. | Could | 7 |

### A normal day with the app

1.  09:00. Press the hotkey, choose Acme, 2 hours, issue ACM-412. Menu bar starts counting down.
2.  The panel lists three sessions in Acme folders. One says "waiting for you". Click Focus and iTerm2 comes forward on that tab.
3.  09:50. Break chime. The five minutes are recorded as a break and still count toward the hours for ACM-412, because Acme counts breaks.
4.  11:00. Block ends with a sound. The panel shows a meeting at 11:30, so it suggests a 25 minute Globex block.
5.  17:30. Review screen: 3 h 40 min on ACM-412, 1 h 30 min on GLX-88. Adjust, press Send, done.

### Rules worth fixing early

- Exactly one running entry at a time, across all devices
- A time entry has one kind: work, break or meeting
- Pausing ends the entry and resuming starts a new one, so history is always a list of real intervals
- Timer entries never overlap. Starting a block or switching first ends whatever is running, at the same moment, and after the clock moves back a new entry starts after the latest timer entry. An entry added or changed by hand is refused when it would overlap any other entry, the running one counted up to now. Overlaps with calendar entries are handled when those arrive
- An entry of a running block takes only a note, and cannot be deleted, until the block ends. The timer derives the block's end from the gaps between its entries
- Tracked time is shown in whole minutes, rounded down per entry, and every total is the sum of those minutes. Stored entries keep their seconds
- A block keeps counting down during a break, and a break never runs past the end of its block. A paused block never runs out: its end moves later for as long as the pause lasts
- When the Mac sleeps or the app quits during a block, the block still ends at its planned time, and the time in between counts as worked. Idle detection refines this in phase 2
- An action that does not fit the moment, such as Pause with nothing running, is refused and changes nothing
- Idle detection: after 10 minutes without input the app asks whether to keep or discard that time
- Jira rounding happens only in the review screen, never in stored data. The default step is 15 minutes and each workspace can set its own
- The hours you send to Jira can differ from the hours tracked. The app keeps both numbers and shows the difference
- A break inside a block belongs to the task of that block. By default it counts toward the hours sent to Jira, and each workspace can switch that off. Time between blocks is never counted
- Every meeting counts unless you declined it, so invitations you have not answered count too
- Out of office is never time worked. It marks the workspace whose calendar it is in as off for those hours, and the whole day when nothing else is planned. The app then stays quiet, and starting a block anyway takes one confirmation

How each screen looks and behaves is in [design.md](design.md).
