# Features

Every feature with its priority and phase, a normal day with the app, and the rules about time.

Part of the product spec. First written as draft 13 of the product spec, 15 November 2026.

## Features and priorities

Must = needed for the app to be worth opening daily. Should = planned, later phase. Could = only if cheap.

| Area | What it does | Priority | Phase |
| --- | --- | --- | --- |
| **Workspaces** | Any number of workspaces that you create, rename, recolor, reorder and archive yourself. Each has a color, a default block length and rhythm, its own rounding and break rules, its projects, and optionally a calendar. Folders and an issue tracker belong to its projects, not to the workspace. Acme, Globex and Personal are sample data throughout this spec. | Must | 1 |
| **Projects** | Each workspace holds its own projects, with a name, an order and an archive. A project has the folders that belong to it, kept on this Mac only, and later its issue tracker. A project's time can be switched off from tracking, for things you do but do not log: its sessions are still listed, and the app never asks to time it. A block or entry names only a tracked project of its own workspace. The model arrives in phase 1, the screen in Settings with the folders and the tracking switch in phase 3, and the issue tracker in phase 4. | Must | 1 to 4 |
| **Time blocks** | "Next 2 hours: Acme." Countdown in the menu bar, pause, extend, switch workspace, end early. Each block is saved as time entries. | Must | 1 |
| **Alerts** | System notification and sound when a block, focus interval or break ends. Optional warning 5 minutes before. Selectable sounds. | Must | 1 |
| **Menu bar overview** | Menu bar shows workspace and remaining time. Click opens a compact panel with the current block and four quick actions. One more step expands it to sessions, the plan for today and totals. | Must | 1 |
| **Quick functions** | Quick-start presets, a right-click menu on the menu bar item, and a command bar on a global shortcut for starting a block, pausing, taking a break and jumping to the waiting session. | Should | 1 to 3 |
| **History** | Day, week and month views. Totals per workspace, project and issue. Edit or split entries. CSV export. | Must | 1 to 2 |
| **Focus rhythm** | Split a block into focus intervals and breaks, with a long break after a number of rounds. Pomodoro presets (25/5, 50/10) or custom, and each workspace names its default, or none. After a break, work resumes by itself or waits for you, as the preset says. Meetings inside a block come with the calendar in phase 5. Breaks are recorded as their own kind, and each workspace decides whether they count toward the logged hours. | Should | 2 |
| **Agent sessions** | Live list of Claude Code sessions on this Mac: project, profile, state (working, waiting for you, idle), last activity. A session belongs to the project whose folder it runs in, and through it to a workspace. A session in no project's folder is listed under "Other", by its folder's name. The list needs no running block, and it lists the sessions of projects whose time is not tracked too. Other agents, Codex first, plug in later as adapters. | Must | 3 |
| **Focus terminal** | One click brings the terminal that holds a session to the front: the exact tab in Terminal and iTerm2, the right window in VS Code and Cursor. A keyboard switcher cycles through sessions. | Must | 3 |
| **Needs-you alerts** | Notification when an agent is waiting for permission or input, with a button that focuses its terminal. Also with no block running, and for projects whose time is not tracked. | Should | 3 |
| **Multiple Claude accounts** | Each Claude Code profile folder is one account. For example personal, client and work. Every session carries its profile as a label, and more profiles can be added by path. | Should | 3 |
| **Issue trackers** | Connect issue trackers, Jira and Trello first, each through its own adapter. A project names its tracker. Pick an issue for the current block from "assigned to me" or by key. Time entries carry the issue. | Should | 4 |
| **Worklogs** | For a tracker that keeps time, such as Jira. Review screen: entries grouped per issue and rounded to your rule. Before sending you can change the hours, the comment and the issue, or leave a row out. After sending you can still change the hours or remove the worklog, and the app updates the tracker. A tracker that keeps no time gets no worklogs. | Should | 4 |
| **Calendar** | Meetings from company Google accounts shown on today's timeline. "Free until 14:00" hint when you start a block. Meetings can become meeting entries automatically. Every meeting counts unless you declined it. An Out of office entry is not a meeting: it marks the workspace as off for the day, and the app shows it and stays quiet. | Should | 5 |
| **Day plan** | Lay out the whole day as blocks around your meetings, in the morning or the evening before. The plan shows in the panel, a planned block starts with one click when its time comes, and history compares plan with reality. | Should | 5 |
| **iCloud sync** | Workspaces, projects, blocks, entries, focus presets and issue links sync between your devices through your Apple ID. A project's folders stay on each Mac. | Should | 6 |
| **iPhone app** | Start, stop and switch blocks, see today and history, Live Activity with the countdown on the Lock Screen. | Should | 6 |
| **First-run setup** | A short guided start for a new user: create workspaces, find the Claude Code profiles, install the hook with consent, show how to add a calendar account to the Mac, and ask for permissions one at a time with the reason for each. | Should | 8 |
| **Install and updates** | Free and open source. A signed and notarized download from the project page that updates itself, so other people can use the app without Xcode. | Should | 8 |
| **insight-flow** | For repos that use insight-flow, show the active task next to the session and offer it as the label for the time entry. | Could | 7 |
| **Desktop widget** | macOS and iOS widget with the current block and today's totals. | Could | 7 |

### A normal day with the app

1.  09:00. Press the hotkey, choose Acme, 2 hours, issue ACM-412. Menu bar starts counting down.
2.  The panel lists three sessions in Acme's projects. One says "waiting for you". Click Focus and iTerm2 comes forward on that tab.
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
- A block keeps counting down during a break, and a break never runs past the end of its block. +15 during a break adds the 15 minutes to both the break and the block, so the work left after the break stays the same. A paused block never runs out: its end moves later for as long as the pause lasts
- A block with a rhythm keeps its own copy of its preset's plan, made when it starts. Editing or deleting the preset later never changes it. A block started without a preset, and every block from before presets, has no rhythm and runs as before
- The rhythm is derived from the block's stored times and never stored. Paused time moves it later, as it moves the block's end, and a due break waits while paused. A clock moved back is read as the block's latest stored time
- A due planned break only tells, and nothing starts by itself. If you keep working for its planned length, it counts as skipped: it leaves no entry, and the next focus interval starts then. A break taken while one is due is the planned one, whatever its length
- A round ends with any break: planned, taken by hand or skipped. Every Nth break is the long one. A break taken by hand during focus ends that round, and the next focus interval starts when it ends
- The block's end comes first. A planned break that would end at or after it is left out, and a long break that does not fit is dropped, not replaced by a short one. +15 keeps its rules, and the plan follows, so it can bring a dropped break back
- In a block with a rhythm, a break that ends by itself either resumes work or leaves the block paused until Resume, as the preset says, and the block's end moves later while it waits. Ending a break by hand always starts work, and a block without a rhythm always resumes. Pausing during a break ends it, and Resume then starts a full focus interval
- When the Mac sleeps or the app quits during a block, the block still ends at its planned time, and the time in between counts as worked. Idle detection refines this in phase 2
- An action that does not fit the moment, such as Pause with nothing running, is refused and changes nothing
- Idle detection: after 10 minutes without input the app asks whether to keep or discard that time
- Rounding for a tracker happens only in the review screen, never in stored data. The default step is 15 minutes and each workspace can set its own
- The hours you send to a tracker can differ from the hours tracked. The app keeps both numbers and shows the difference
- A break inside a block belongs to the task of that block. By default it counts toward the hours sent to a tracker, and each workspace can switch that off. Time between blocks is never counted
- A break can also be taken with nothing running, such as for lunch after ending the block. It is not stored, counts toward nothing, and is left out of untracked time. Nothing starts when it ends
- Every meeting counts unless you declined it, so invitations you have not answered count too
- Out of office is never time worked. It marks the workspace whose calendar it is in as off for those hours, and the whole day when nothing else is planned. The app then stays quiet, and starting a block anyway takes one confirmation

How each screen looks and behaves is in [design.md](design.md).
