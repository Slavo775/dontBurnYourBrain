# Design

How the app looks and behaves, surface by surface.

The drawn screens are in [../design/prototype/index.html](../design/prototype/index.html). Open it in a browser. Several of them are live: the compact panel, Jira review and the Workspaces settings. When this text and the prototype disagree, the prototype wins on looks and this text wins on behaviour. Tell the owner about the difference either way.

Acme, Globex, Personal and the issue keys are sample data. Users create their own workspaces.

## Principles

- Every surface has one job, and the rest sits one step deeper.
- One strong color per screen: the color of the workspace. Everything else stays neutral.
- Time left is the largest thing on screen. Seconds are small on purpose.
- Light and dark from the first screen.
- The app only asks. It never starts a timer, sends a worklog or changes another tool's settings by itself.

## The four surfaces

| Surface | Opens with | Job |
|---|---|---|
| **Menu bar item** | Always visible | Whose time is running and how much is left |
| **Compact panel** | A click on the menu bar item | The running block and four actions |
| **Expanded panel** | ⌘E in the panel | Sessions, the plan for today, totals |
| **Window** | ⌘O | Day plan, history and Jira review |

Settings have their own window, opened with ⌘ and comma.

## Colors and type

The prototype draws the app at real macOS sizes in the system font. These values come from its CSS (`style.css` and `design.css`). In SwiftUI, use system materials, semantic colors and system text styles wherever they give the same look, and take the values below for what the system does not provide.

| Token | Light | Dark | Used for |
|---|---|---|---|
| surface | `#ffffff` | `#18201d` | Panels and windows |
| sunken | `#e9edeb` | `#0c110f` | Buttons, rows, the empty part of the progress strip |
| line | `#d3dad7` | `#2b3632` | Dividers and outlines |
| ink | `#16201d` | `#e6ece9` | Text |
| muted | `#5a6964` | `#96a59f` | Secondary text |
| ok | `#1f7a3d` | `#6bcf8a` | A working session, a sent worklog, a switch that is on |
| warn | `#9a5b00` | `#e2b25a` | A session that needs you, time not yet in Jira |
| warn, soft | `#f6e7c8` | `#392b10` | The background of the needs-you strip |
| bad | `#a8322a` | `#ee8c83` | Errors |

Workspace colors come from a palette of six, each with a light and a dark value. Store the palette key, not the hex value, so dark mode works.

| Key | Light | Dark |
|---|---|---|
| a | `#0b6e5c` | `#4fc3a8` |
| b | `#c2571a` | `#e88b55` |
| c | `#4f5bb5` | `#8e99ea` |
| d | `#a8386a` | `#f08fb5` |
| e | `#86690a` | `#dcc056` |
| f | `#566670` | `#a9b7c0` |

Type: the system font at 13 pt in panels, 12 pt for secondary lines. The countdown is 54 pt, rounded, semibold, with the seconds at half that size and half the opacity. Every number that changes uses tabular figures, so nothing shifts as it ticks.

## Menu bar item

The prototype draws five states as tiles. Its live panel shows a sixth, paused.

| State | Shows |
|---|---|
| **Block running** | A dot in the workspace color, the workspace name, and hours and minutes left: `Acme 1:24`. In the last five minutes it shows minutes and seconds |
| **Paused** | The dot, the name and "paused": `Acme, paused` |
| **On a break** | A cup icon and the break time left: `4:12` |
| **Nothing running** | An outline dot. After 15 minutes it also shows how long nothing has been tracked: `0:15` |
| **Agent waiting** | Any state above plus an amber badge with the number of waiting sessions. The panel then opens with that session on top |
| **Day off** | An icon and "Off". Out of office leaves nothing planned for today, or the user took the day off. Untracked time is not counted |

## Compact panel

328 pt wide, 20 pt padding, corners rounded at 16 pt.

### A block is running

From top to bottom:

1. **Header.** The workspace dot and name, the issue below it (`ACM-412 Checkout redirect`), and a button that expands the panel.
2. **Countdown.** `1:24` large with `:10` small. Below it one line: "left of 2:00, break in 19 min".
3. **The block as a strip.** Filled up to now. Pale gaps mark the breaks, so the rhythm and the next break are visible.
4. **Four actions in fixed places:** Pause, Break, +15 min, Switch.
5. **Needs-you strip,** amber, only when an agent is waiting: "acme-web needs you", "Claude (work) in iTerm2", and a Focus button. Working and idle sessions stay one step away.
6. **Footer.** The next meeting ("Next: Sprint sync at 11:30") and a link to the sessions ("3 sessions").

What the actions do:

| Action | Effect |
|---|---|
| **Pause** | The countdown stops and the running entry ends. The button becomes Resume, the digits dim, the menu bar says "paused". Resume starts a new entry, and the block ends later by the length of the pause |
| **Break** | A break entry starts inside the block, with its own countdown, five minutes by default. The button becomes End break. When the break is over, work continues. The block still ends at its planned time |
| **+15 min** | Adds 15 minutes to the block |
| **Switch** | Shows the quick start list under the title "Switch to", with a Back button. Choosing a workspace ends the current block and starts a new one for that workspace, at its default length |

In the prototype the block's countdown stands still during a break. That is a shortcut of the drawing. The rule in [features.md](features.md) holds: a break is part of the block.

End block is not among the four. It lives in the right-click menu and the command bar.

### Nothing is running

- Title "Nothing running", and below it "Free until 11:30" when the calendar knows.
- One row per workspace, in the order from Settings: the dot, the name, the default block length, the last issue, and a number key. A click or the number starts the block.
- "Custom block", ⌘N, opens a short form: workspace, length, issue.
- Footer: "Today: 0:10 tracked".

When the block ends, a sound plays, a notification appears and the panel returns to this view.

## Expanded panel on the Mac

Decided: the Mac gets one wide panel, the iPhone gets pages.

⌘E widens the panel to about 780 pt, and it stays wide until it is collapsed. Two columns:

- **Left, 320 pt.** The compact panel's header, countdown, strip and four actions. Below them "Today": the day as a short list of blocks and meetings with their start times and lengths.
- **Right.** "Sessions" with filter chips (All 5, Acme 3, Globex 1, Personal 1), then the sessions in three groups:
  - **Needs you:** project, session title, "Claude (work) in iTerm2", a Focus button and ⌘1.
  - **Working:** the same row with ⌘2, ⌘3.
  - **Idle:** dimmed, with the time since the last activity.
- **Footer.** Today's totals per workspace, "Log time", and "Open window ⌘O".

⌘1 to ⌘9 jump straight to a session while the panel is open. A session's state shows as a small dot on its icon: amber for waiting, green for working, grey for idle.

## Pages on the iPhone

The phone keeps the panel small and shows one thing at a time. A bar at the bottom switches between four pages: Now, Today, History and Log. Sessions are read-only on the phone, because the terminals live on the Mac. The prototype also draws these pages at Mac size for comparison. On the Mac they are not built.

- **Now:** the same block, countdown, strip and four actions, and a line when a session on the Mac needs you.
- **Today:** the day as a list, with free time between items ("30 min free").
- **Log:** the day's tasks with tracked and rounded hours, − and + on each, and "Send 2 worklogs (5:00)".
- **Lock Screen:** a Live Activity with the workspace, the issue, the countdown, and Pause and Break.

## Quick functions

Three ways to act without opening the panel.

### Command bar

Opened with ⌥ Space from anywhere. About 580 pt wide, one text field, results below.

- Typing `ac 2h 412` offers "Start Acme for 2 h" with the issue `ACM-412`. Return starts it. ⌘ Return starts it without an issue.
- Other things to type: `globex 1h`, `break 10`, `+15`, `focus web`, `log`.
- With the field empty, one key acts at once: P pause, B break, F focus the waiting session, 1 to 3 the quick start presets.
- A day off can be taken from here too, with no calendar involved.

### Right-click menu on the menu bar item

Pause, Take a break, Add 15 minutes, End block. Then the quick start presets ("Start Acme for 2 h"). Then Focus the waiting session, and Open the window ⌘O.

### Session switcher

Hold ⌥ and tap Tab to step through the sessions, and release to jump there. The strip shows one tile per session and names the one that needs you.

### Shortcuts

| Action | Keys |
|---|---|
| Open the command bar | ⌥ Space |
| Switch between sessions | ⌥ Tab |
| Pause, break, focus the waiting session | ⌥ Space, then P, B or F |
| Start preset 1 to 3 | ⌥ Space, then 1, 2 or 3 |
| Expand or collapse the open panel | ⌘E |
| Jump to a session while the panel is open | ⌘1 to ⌘9 |

Only ⌥ Space and ⌥ Tab are global. Both can be changed in Settings, in case they clash with something.

## The window

Opened with ⌘O. It is used a few times a week, so it can afford detail. A sidebar on the left, 210 pt wide: Today, History, Sessions and Jira review with a count of what is waiting. At the bottom of the sidebar, last week's totals per workspace, which double as the legend for the charts.

### Today: plan the whole day

- A timeline with one row per hour. Meetings come in from the calendars and are drawn in grey. They are fixed.
- Blocks go around them. Click a gap to add one ("30 min free, click to add a block"), drag to move, drag an edge to resize. The running block says "running, 1:24 left", the others "planned".
- "Plan tomorrow" switches to the next working day, so the plan can be made the evening before.
- On the right, a summary: "Planned 6:00 of 8:00", then done and planned hours per workspace and for meetings, and a line such as "2 hours of the day have no plan yet."
- The plan never starts a timer by itself. When a planned block is due, the app asks, and one click or key starts it.

### History

- Day, week and month. A bar chart of hours per day, in workspace colors.
- A table per task: the issue and its title, the workspace, the time, and the Jira state: "3:11 to send" in amber, "logged", or "no Jira issue".
- Amber always means tracked time that is not in Jira yet. Jira review collects exactly that.

### Jira review: the hours are yours to change

One row per task for the chosen day:

- a checkbox, the issue and its title
- **Tracked:** what the timer measured, with the part spent in breaks ("3:11, 0:20 in breaks")
- **Goes to Jira:** the tracked time rounded by the workspace rule, with − and + to change it in steps, or a typed value
- a comment for Jira
- a state: to send, in Jira, changed since it was sent, or left out

Below: "Tracked 5:00, going to Jira 5:00", and one button, "Send 2 worklogs (5:00)".

- A task without a Jira issue stays out until one is chosen.
- Nothing leaves until the button is pressed.
- After sending, changing a number offers to update that worklog in Jira. Removing a row deletes the worklog there.

## Out of office

An Out of office entry in a calendar is not a meeting. It says the user is not working, so the app marks the day and stays quiet.

- It belongs to the workspace whose calendar it is in. In the quick start list, that workspace's row is hatched and says "Out of office all day". Starting a block for it anyway takes one confirmation. The other workspaces start as usual.
- When that leaves nothing planned for today, the whole day is off. The menu bar says "Off", and the panel says "Day off", "No reminders today", with "Start a block anyway" below.
- In the day plan, a band at the top says "Globex is out of office all day", with a "Work anyway" button. That workspace's meetings are hatched and marked "not counted", and its blocks are not suggested. The summary shows "out of office" instead of hours for it.
- If it covers only part of a day, only those hours are off.
- Out of office is never a meeting and never time worked. It is not logged anywhere.
- History keeps the mark, so a short week does not look like forgotten time.
- The user can also take a day off by hand, from the command bar.

## Settings

Seven tabs: General, Workspaces, Rhythm, Sessions, Jira, Calendars, Shortcuts.

### Workspaces

A list on the left with + and −, the chosen workspace on the right:

- name and color, from the six swatches
- default block length, and rhythm ("25 min focus, 5 min break")
- folders that belong to it. A session started in one of them shows up under this workspace
- the Jira site and project, the rounding step, and a switch: "Breaks count as working time and go to Jira"
- the calendar
- its quick start key ("Shown on key 1")

The order of the list is the order of the quick start presets and their number keys. Removing a workspace archives it: it leaves the menus and its history stays. A workspace without Jira never appears in Jira review.

### Sessions

- **Claude Code profiles.** Each Claude account is its own profile folder. The app finds them, lists them with their path, and shows per profile whether its hook is installed, with an "Install hook" button. A profile can also be added by its folder.
- **Other agents.** Codex is listed as "added later".
- **Terminals.** iTerm2 and Terminal jump to the exact tab. VS Code and Cursor bring the window forward. Each shows whether macOS has allowed the app to control it, with an "Allow" button.

## Sounds

- A soft chime when a focus interval ends
- A different chime when a break ends
- A longer tone when the block ends
- A short tick when an agent needs you, which can be muted during focus

## Which phase builds what

| Surface or part | Phase |
|---|---|
| Menu bar item: running, paused, break, nothing running | 1 |
| Compact panel: countdown, strip, four actions, quick start, custom block | 1 |
| Settings: Workspaces (name, color, default block, order, archive) | 1 |
| Window: Today as a list, simple history | 1 |
| Right-click menu: the block actions | 1 |
| Break gaps in the strip, "break in", rhythm settings | 2 |
| Command bar, the full right-click menu, week and month charts | 2 |
| Needs-you strip, expanded panel, session switcher, Settings: Sessions, the amber badge | 3 |
| Issue on a block, Jira review, Settings: Jira | 4 |
| Day plan, next meeting, "free until", Out of office, the Off state, Settings: Calendars | 5 |
| iPhone pages and the Live Activity | 6 |

A part that belongs to a later phase is left out until then. It is not shown disabled.
