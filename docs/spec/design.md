# Design

How the app looks and behaves, surface by surface.

The drawn screens are in [../design/prototype/index.html](../design/prototype/index.html). Open it in a browser. Several of them are live: the compact panel, Jira review and the Workspaces settings. When this text and the prototype disagree, the prototype wins on looks and this text wins on behaviour. Tell the owner about the difference either way.

Where this text is ahead of the prototype: the prototype draws folders and a Jira link on each workspace, a Jira tab in Settings and a Jira review, and no projects. Here the projects of a workspace hold the folders and the issue tracker, the tab is Trackers, and the review is Time review. The prototype also does not draw the End block row, "Break for" or a break with nothing running.

Acme, Globex, Personal and the issue keys are sample data. Users create their own workspaces.

## Principles

- Every surface has one job, and the rest sits one step deeper.
- One strong color per screen: the color of the workspace. Everything else stays neutral.
- Time left is the largest thing on screen. Seconds are small on purpose.
- Light and dark from the first screen.
- The app only asks. It never starts a timer, sends a worklog or changes another tool's settings by itself. For a project whose time is not tracked, it does not even ask.

## The four surfaces

| Surface | Opens with | Job |
|---|---|---|
| **Menu bar item** | Always visible | Whose time is running and how much is left |
| **Compact panel** | A click on the menu bar item | The running block and four actions |
| **Expanded panel** | ⌘E in the panel | Sessions, the plan for today, totals |
| **Window** | ⌘O | Day plan, history and time review |

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
| warn | `#9a5b00` | `#e2b25a` | A session that needs you, time not yet sent to a tracker |
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
| **On a break** | A cup icon and the break time left: `4:12`. The same for [a break with nothing running](#a-break-with-nothing-running) |
| **Nothing running** | An outline dot. After 15 minutes it also shows how long nothing has been tracked: `0:15` |
| **Agent waiting** | Any state above plus an amber badge with the number of waiting sessions. The panel then opens with that session on top |
| **Day off** | An icon and "Off". Out of office leaves nothing planned for today, or the user took the day off. Untracked time is not counted |

How the first four states behave today:

- Times left are rounded down. A block shows `h:mm` until less than five minutes are left, so the seconds start at `4:59`. A break always shows `m:ss`.
- Untracked time counts from the end of the latest entry that ended today, else from the app's start, but never from before the start of today. A break with nothing running is left out: when it ended later than that, untracked time counts from its real end. That is its planned end when it ran out, or the moment it was ended by hand or by a block start. It never counts from a moment in the future or before today, and this holds after a restart.
- The item redraws just after the shown digits change, and at least once a minute. At `0:00` the block or break is closed on the next tick.
- A long workspace name is cut to 16 characters, "…" included, and never drawn wider than 116 pt.
- Without a store the item shows the outline dot and never ticks.
- The Dev build draws a small "DEV" 4 pt after the label, 9 pt bold, in the secondary label color, and VoiceOver reads ", Dev build" after the label, such as "Acme 1:23, Dev build". The marker makes the item about 25 pt wider, so on a notched display it is hidden sooner. The 116 pt limit for the name is the same. Release shows no marker.
- A click, or VoiceOver's press, opens and closes the compact panel. A right-click or a Control-click opens the menu, described under [Right-click menu on the menu bar item](#right-click-menu-on-the-menu-bar-item).
- The item also offers a "Show menu" accessibility action, which accessibility clients such as VoiceOver can perform. It closes the panel and opens the same menu, with no mouse. While the menu is open, it does nothing. It has been checked through the accessibility API, not yet with VoiceOver itself.

Phase 0 showed a plain clock here instead. Phase 1 replaced it.

### Limits

Found while building the phase 0 clock and the phase 1 states. They hold for every state above.

- The item is an AppKit `NSStatusItem`, not SwiftUI's `MenuBarExtra`, because `MenuBarExtra` offers either a menu or a window on a click, not a panel on the click and a menu on the right-click.
- The label is drawn as one image, so the dot, the name and the digits stay together, in tabular figures. (Under `MenuBarExtra`, a `Text` label lost its font, so an image was the only way.) The image's accessibility description, and the button's accessibility title, carry the same text, such as "On a break, 4:12 left", so VoiceOver reads it.
- The "Show menu" action sits on the button's cell, not on the button. On macOS 27, the element MenuBarAgent shows accessibility clients for the item reads the cell's actions. A standard `AXShowMenu` would need a subclass of AppKit's private status bar button cell, so the item offers a custom action instead. The action opens the menu on the run loop's next pass, so the client's request returns at once.
- The image is not a template image. A template image is drawn in one color and would lose the workspace's dot. Instead it is drawn each time the menu bar draws it, in the menu bar's own appearance: the text and outline in the label color, the dot in the workspace color.
- Because it is not a template image, the item does not get the menu bar's vibrancy, and it is not dimmed on an inactive display.
- The label is updated by a `Timer`, which sets the item's image only when the label changes. A `TimelineView` inside a `MenuBarExtra` label kept the main thread busy and hung the app.
- The item and its menu follow the menu bar's appearance, which follows the system. The app's own appearance does not reach them. It does reach the compact panel.
- On a notched built-in display, the item can sit behind the hidden-items chevron when the menu bar is full.
- Under `MenuBarExtra`, while the menu was open on one display, the item's copy on another display stopped updating until the menu closed. This has not been checked again with `NSStatusItem`.
- Updating every second, as the phase 0 clock did, cost about 5 % of one core in the Debug build, mostly macOS redrawing the item's copy for each display and Space. The item now does that only while it shows seconds. While the compact panel is open, the countdown ticks every second, but only the panel redraws.
- Under `MenuBarExtra`, on macOS 26, the console showed "It's not legal to call -layoutSubtreeIfNeeded on a view which is already being laid out" once per launch. It came from AppKit setting up the status item for each display (`-[NSSceneStatusItem _connectVariantViewScene:]` → `-[NSStatusItem _setDisplayIdentifier:]` → `-[NSWindow _setFrameCommon:display:fromServer:]` → `-[NSWindow _layoutViewTree]`), and it also appeared with a plain SF Symbol label. It is not ours and needs no fix. This has not been checked again with `NSStatusItem`.

## Compact panel

328 pt wide, 20 pt padding, corners rounded at 16 pt.

### A block is running

From top to bottom:

1. **Header.** The workspace dot and name, the issue below it (`ACM-412 Checkout redirect`), and a button that expands the panel.
2. **Countdown.** `1:24` large with `:10` small. Below it one line: "left of 2:00, break in 19 min".
3. **The block as a strip.** Filled up to now. Pale gaps mark the breaks, so the rhythm and the next break are visible.
4. **Four actions in fixed places:** Pause, Break, +15 min, Switch.
5. **End block,** one quieter row under the four.
6. **Needs-you strip,** amber, only when an agent is waiting: "acme-web needs you", "Claude (work) in iTerm2", and a Focus button. Working and idle sessions stay one step away.
7. **Footer.** The next meeting ("Next: Sprint sync at 11:30") and a link to the sessions ("3 sessions").

What the actions do:

| Action | Effect |
|---|---|
| **Pause** | The countdown stops and the running entry ends. The button becomes Resume, the digits dim, the menu bar says "paused". Resume starts a new entry, and the block ends later by the length of the pause. Pausing during a break ends the break, and Resume starts work |
| **Break** | Opens "Break for", where the length is chosen. A break entry then starts inside the block, with its own countdown. The button becomes End break. When the break is over, work continues. The block still ends at its planned time, and a break that would run past it stops there, so for lunch the block is ended first. While the block is paused, Break is disabled in the button, the B key and the menu: resume first (the owner's decision) |
| **+15 min** | Adds 15 minutes to the block. On a break it adds them to the break too, so the work left after the break stays the same. This is the owner's decision on card 44 |
| **Switch** | Shows the quick start list under the title "Switch to", with a Back button. Choosing a workspace ends the current block and starts a new one for that workspace, at its default length |

In the prototype the block's countdown stands still during a break. That is a shortcut of the drawing. The rule in [features.md](features.md) holds: a break is part of the block.

End block is not among the four. It is a quieter row under them, and it also lives in the right-click menu and the command bar. It ends the running entry and the block now, with no confirmation, and starts nothing else. During a break the break entry ends and no work entry starts. While paused, nothing is reopened. The panel returns to "Nothing running". When the block's time is up, the same happens at its planned end. The row in the panel is the owner's decision on card 43. The prototype does not draw it.

How the panel behaves today, in phase 1:

- It is a borderless panel under the menu bar item. It takes the keys as soon as it opens, without bringing the app to the front.
- It shows the workspace dot and name, the countdown, one line ("left of 2:00", "Paused", or "On a break, then back to Acme"), the strip, the four actions, the End block row, and the footer "Today: 1:42 tracked". The issue, the expand button, the needs-you strip, the next meeting and the sessions link come in later phases.
- The countdown shows `h:mm` large and `:ss` small from one hour left on, and `m` with `:ss` below that. During a break the strip is filled in the muted color.
- The End block row is drawn like the outlined "Custom block" row, 8 pt under the four actions: a small muted stop icon, "End block", and the key hint E on the right. It shows only while a block runs, is paused or is on a break, so not on a break with nothing running. VoiceOver reads it as one element, "End block".
- "Break for" opens from Break or B while working, and from "Take a break" with nothing running. Like Switch, it has a title, a Back button and rows: 5, 15, 30 and 60 min on the keys 1 to 4. There is no typed length. The last length used is preselected: its row has a 2 pt ink outline and the Return key ↵ beside its number, and Return or keypad Enter starts it. VoiceOver reads the rows as "5 minutes" to "60 minutes", the preselected one as selected. The length is remembered across launches. It is 5 min at first, and a stored value outside the list becomes 5.
- Keys: P pauses and resumes, B opens "Break for" while working and ends a break, + adds 15 minutes, S opens Switch, E ends the block, Escape closes the panel. On a break with nothing running, B ends it, + lengthens it and S opens Switch, and P and E do nothing. P, B, +, S and E act on the running block or break, and not in Switch or "Break for". With nothing running only B is taken, and it opens "Break for" when there is a store. 1 to 9 start a workspace in the "Nothing running" list and in Switch. In "Break for", 1 to 4 start a break of that length, Return or keypad Enter starts the preselected one, and Escape closes the panel, as in Switch. ⌘N opens the custom block form, but not from "Break for". In the form, Return or keypad Enter starts, and Escape goes back to the list instead of closing the panel. Each key acts once per press, and a held key does not repeat. ⌘O closes the panel and opens [the window](#the-window). ⌘N and ⌘O are the only keys with ⌘, ⌃ or ⌥ that are taken, each with ⌘ alone; the others are ignored.
- Switch uses the same rows as "Nothing running": every active workspace in the order from Settings, the running one included, with the dot, the name, the default length and the number key. Back returns to the running block.
- The panel closes on Escape, on a second click on the item, on a right-click, on the item's "Show menu" action, and when it loses focus, such as on a click elsewhere.
- The countdown ticks every second only while the panel is open.
- It follows the app's appearance, so `-DontBurnAppearance` reaches it. The item and its menu follow the system.
- Today's tracked total counts work and meetings always, and a break only when its workspace counts breaks. Entries are clipped to today and to now. It is the window's Today total: the sum of each entry's whole minutes, rounded down per entry.
- With nothing running, it shows the list described below. Without a store, it shows only "Nothing running", with no rows, no footer and no keys.
- While the app asks for the notification permission, one line under the actions says "Allow notifications to hear when a block or break ends". It goes away when the system prompt is answered, and never shows after a refusal.

### Nothing is running

- Title "Nothing running", and below it "Free until 11:30" when the calendar knows.
- One row per workspace, in the order from Settings: the dot, the name, the default block length, the last issue, and a number key. A click or the number starts the block.
- "Custom block", ⌘N, opens a short form: workspace, length, issue.
- The needs-you strip when an agent is waiting, as while a block runs. Sessions need no block.
- Footer: "Today: 0:10 tracked".

When the block ends, a sound plays, a notification appears and the panel returns to this view.

What phase 1 builds:

- Title "Nothing running", without "Free until".
- One row per active workspace in the order from Settings: the dot, the name and the default length, without the last issue. The first nine get the keys 1 to 9. The list scrolls only with more than nine.
- A click or a number key starts a block at the workspace's default length.
- "Custom block", ⌘N, opens a form with a Workspace picker, a Length picker and Start. The lengths are the fixed list Settings offers, preselected to the workspace's default, and again when the workspace changes. There is no typed length and no issue field yet. ⌘N works only with nothing running and at least one workspace.
- "Take a break", on the key B, under "Custom block" and drawn like it, outlined. It opens "Break for" and starts [a break with nothing running](#a-break-with-nothing-running). It shows only with a store.
- Footer "Today: h:mm tracked".
- No workspaces: the note "No workspaces yet", the "Take a break" row, because a break needs no workspace, and a "Settings…" button that opens Settings.
- When a block ends by itself, the panel returns to the list, and the sound and the notification from [Sounds and notifications](#sounds-and-notifications) announce it.

### A break with nothing running

A break of the length the owner needs, such as lunch, also when no block runs. This is the owner's decision on card 44. For lunch during a block, he ends the block first. The prototype draws neither this break nor "Break for".

- **Starting.** From the "Take a break" row in "Nothing running" or under "No workspaces yet", which opens "Break for", or from the "Take a break" submenu in the right-click menu. Both offer 5, 15, 30 and 60 min, and both need a store.
- **Not stored.** It is not a time entry, names no workspace and counts toward nothing, so Today and History stay as they are. It is left out of untracked time, as the [Menu bar item](#menu-bar-item) says.
- **The menu bar item** shows the cup and the time left as `m:ss`, as on a break in a block.
- **The panel** has a muted cup and "Break" for a header, the countdown, "No block running" under it, the strip, which fills in the muted color as the break is used up, the four actions and the footer. Pause is disabled. End break ends it with no sound and returns to "Nothing running". +15 lengthens it, but a break never runs longer than a day from its start: past that, +15 is refused. Switch opens the start list, and choosing a workspace ends the break and starts that block. With no workspaces, Switch is disabled. There is no End block row.
- **The right-click menu** holds End break and Add 15 minutes, with no Pause and no End block.
- **When it runs out,** the break-end alert plays its sound and shows "Break is over" and "Start a block when you're ready." The panel returns to "Nothing running", and nothing starts by itself. The first break asks for the notification permission, as the first block does.
- **Starting a block** in any way ends the break first, with no sound.
- **Restarts.** It survives quitting the app. A break that ended while the app was quit plays no sound at launch.
- **Where it is kept.** The app's own defaults hold the latest break with nothing running, running or finished, as `break.idle.start` and `break.idle.end`, and the last length used as `break.lastMinutes`. None of it is in SwiftData, so the data model did not change. Under `-DontBurnSampleData` all three stay in memory, and the defaults are never read or written.
- **Checked when read.** A stored break counts only when both values are dates, in order, at most a day long, started by now and ending at most a day after now. Anything else is dropped and removed from the defaults. Every time shown is capped, so no stored value can crash the app.
- **A known limit.** If the clock moves back to between a finished break's start and its end, that break runs again until its end. A `ponytail:` comment in `IdleBreak.swift` names it.
- The rules live in `IdleBreak` and `QuickAction` in `DontBurnCore`.

## Expanded panel on the Mac

Decided: the Mac gets one wide panel, the iPhone gets pages.

⌘E widens the panel to about 780 pt, and it stays wide until it is collapsed. The expand button in the compact panel does the same. Two columns:

- **Left, 320 pt.** The compact panel's header, countdown, strip and four actions. Below them "Today": the day as a short list of blocks and meetings with their start times and lengths.
- **Right.** "Sessions": every agent session on this Mac, the same whether a block runs, is paused or nothing runs. A session belongs to the project whose folder it runs in, and through it to a workspace. Filter chips (All 5, Acme 3, Globex 1, Personal 1), plus "Other" when a session is in no project's folder. Then the sessions in three groups:
  - **Needs you:** the project, or the folder's name when it has no project, the session title, "Claude (work) in iTerm2", a Focus button and ⌘1.
  - **Working:** the same row with ⌘2, ⌘3.
  - **Idle:** dimmed, with the time since the last activity.
- **Footer.** Today's totals per workspace, "Log time", and "Open window ⌘O".

A session of a project whose time is not tracked is listed like any other, and nothing in its row offers to start a block. With no sessions the column says so in one line. Without the hook it says so and links to Settings, Sessions.

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
- Other things to type: `globex 1h`, `break 10`, `+15`, `end`, `focus web`, `log`.
- With the field empty, one key acts at once: P pause, B break, E end the block, F focus the waiting session, 1 to 3 the quick start presets.
- A day off can be taken from here too, with no calendar involved.

### Right-click menu on the menu bar item

Pause, Take a break, Add 15 minutes, End block. Then the quick start presets ("Start Acme for 2 h"). Then Focus the waiting session, and Open the window ⌘O.

Opened with a right-click, a Control-click, or the item's "Show menu" accessibility action. In phase 1, while a block runs, it holds Pause or Resume, "Take a break" or End break, Add 15 minutes and End block, then a divider. "Take a break" is a submenu with 5, 15, 30 and 60 min, disabled while paused. On a break with nothing running it holds End break and Add 15 minutes, with no Pause and no End block, then a divider. Then "Start Acme for 1 h" for the first three active workspaces at their default lengths, then a divider. While a block runs, picking one switches to that workspace. On a break with nothing running, it ends the break and starts that block. Then "Open the window" on ⌘O, "Settings…" on ⌘ and comma, another divider, and "Quit" with the app's name, on ⌘Q. With nothing running it holds the "Take a break" submenu and a divider when there is a store, then the start items, Open the window, Settings and Quit. With no workspaces or no store, the start items are left out.

### Session switcher

Hold ⌥ and tap Tab to step through the sessions, and release to jump there. The strip shows one tile per session and names the one that needs you.

### Shortcuts

| Action | Keys |
|---|---|
| Open the command bar | ⌥ Space |
| Switch between sessions | ⌥ Tab |
| Pause, break, end, focus the waiting session | ⌥ Space, then P, B, E or F |
| Start preset 1 to 3 | ⌥ Space, then 1, 2 or 3 |
| Expand or collapse the open panel | ⌘E |
| Jump to a session while the panel is open | ⌘1 to ⌘9 |

Only ⌥ Space and ⌥ Tab are global. Both can be changed in Settings, in case they clash with something.

## The window

Opened with ⌘O. It is used a few times a week, so it can afford detail. A sidebar on the left, 210 pt wide: Today, History, Sessions and Time review with a count of what is waiting. At the bottom of the sidebar, last week's totals per workspace, which double as the legend for the charts.

### Today: plan the whole day

- A timeline with one row per hour. Meetings come in from the calendars and are drawn in grey. They are fixed.
- Blocks go around them. Click a gap to add one ("30 min free, click to add a block"), drag to move, drag an edge to resize. The running block says "running, 1:24 left", the others "planned".
- "Plan tomorrow" switches to the next working day, so the plan can be made the evening before.
- On the right, a summary: "Planned 6:00 of 8:00", then done and planned hours per workspace and for meetings, and a line such as "2 hours of the day have no plan yet."
- The plan never starts a timer by itself. When a planned block is due, the app asks, and one click or key starts it.

### History

- Day, week and month. A bar chart of hours per day, in workspace colors.
- A table per task: the issue and its title, the workspace, the time, and its state in the tracker: "3:11 to send" in amber, "logged", or "no issue".
- Amber always means tracked time that a tracker keeps but has not received yet. Time review collects exactly that.

### Time review: the hours are yours to change

Only for trackers that keep time, such as Jira. A project whose tracker keeps no time never appears here, and neither does a project whose time is not tracked.

One row per task for the chosen day:

- a checkbox, the issue and its title
- **Tracked:** what the timer measured, with the part spent in breaks ("3:11, 0:20 in breaks")
- **Goes to the tracker:** the tracked time rounded by the workspace rule, with − and + to change it in steps, or a typed value
- a comment for the tracker
- a state: to send, sent, changed since it was sent, or left out

Below: "Tracked 5:00, to send 5:00", and one button, "Send 2 worklogs (5:00)".

- A task without an issue stays out until one is chosen.
- Nothing leaves until the button is pressed.
- After sending, changing a number offers to update that worklog in the tracker. Removing a row deletes the worklog there.

### What phase 1 builds

A list of the day's entries instead of the timeline, and corrections by hand. The rules live in `DayLog` and `EntryEditor` in `DontBurnCore`.

- **Opening.** ⌘O in the compact panel closes the panel and opens the window, once per press. The right-click menu has "Open the window" on ⌘O. The app stays an accessory app with no Dock icon. The window follows `-DontBurnAppearance`.
- **The sidebar** is 210 pt and holds Today and History only. Last week's totals come with the charts in phase 2, the timeline in phase 5, and Sessions and Time review with their phases.
- **A day** shows its total and one total per workspace: active ones in the order from Settings, then archived ones, each only when it has time that day. Below them a list with a column header: Time, Workspace with its dot, Kind, Length and Note.
- **Lengths** are whole minutes, rounded down per entry, and every total is the sum of the rows.
- **The running entry** reads "21:31–now" and counts up.
- **An entry across midnight** shows on both days with its part, "23:30–0:00" and "0:00–0:30", and is stored once.
- **Nothing on the day:** "Nothing tracked".
- **Editing.** A click on a row edits it, and its context menu has Edit… and Delete…. The sheet has Start, End, Workspace, Kind and Note. Kind offers work and break, plus meeting for a meeting. The workspace picker lists the active workspaces, plus the entry's own one if it is archived. Changing the workspace clears the entry's project.
- **Add (+)** stores a manual entry with no block. It starts as the latest free half hour before now on Today, and the latest free hour ending by 10:00 on an earlier day.
- **Delete** asks once.
- **Refusals.** Every change is checked, and a refused one shows its sentence in the `bad` color: no workspace, an end not after the start, an end in the future, or an overlap with another entry, the running one counted up to now.
- **A running block's entries**, paused ones included, take only a note and cannot be deleted until the block ends, because the timer derives the block's end from the gaps between them. This is the owner's decision.
- **History** opens on yesterday, with previous and next and a date picker that stops at yesterday. An earlier day takes the same corrections.
- **Without a store** the window says "The data could not be opened".

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

Seven tabs: General, Workspaces, Rhythm, Sessions, Trackers, Calendars, Shortcuts.

### Workspaces

A list on the left with + and −, the chosen workspace on the right:

- name and color, from the six swatches
- default block length, and rhythm ("25 min focus, 5 min break")
- its projects, described below
- the rounding step, and a switch: "Breaks count as working time"
- the calendar
- its quick start key ("Shown on key 1")

The order of the list is the order of the quick start presets and their number keys. Removing a workspace archives it: it leaves the menus and its history stays.

#### What phase 1 builds

The window has a fixed size of 760 × 470 pt and two tabs: General, with the alert switches described under [Sounds and notifications](#sounds-and-notifications) and the version at the bottom, and Workspaces. The other tabs and rows arrive with their phases.

- **The list** is 220 pt wide, with + and − below it. Rows are reordered by dragging.
- **The form** holds the name, the six swatches, a "Default block" pop-up and "Shown on key N". From the tenth workspace on, it says "No number key".
- **The default block** is chosen from a fixed list: 25 min, 30 min, 45 min, 1 h, 1 h 30, 2 h, 3 h and 4 h. A stored value outside the list is kept and shown as an extra choice.
- **+** creates "New workspace", then "New workspace 2" and so on, counting archived names too. It gets the first color no active workspace uses (key `a` when all six are used), 1 hour, and the last place. Its name is focused and selected.
- **−** archives after one confirmation. Nothing deletes a workspace.
- **Archived workspaces** sit in a collapsible "Archived" section under the list, with dimmed rows. Choosing one shows it read-only with a Restore button. Restore puts it last.
- **No active workspaces:** a centered "No workspaces yet" with "Create a workspace", and below it the archived workspaces, if any, each with Restore.
- **The store could not be opened:** the Workspaces tab says "The data could not be opened".

The prototype does not draw the Archived section, the empty state or the list of block lengths. The owner chose the looks above. The rules live in `WorkspaceRoster` in `DontBurnCore`.

#### Projects, from phase 3

The chosen workspace lists its projects.

- Projects are added, renamed, reordered, archived and brought back. Nothing deletes a project.
- Each has a name, a "Track time" switch, on by default, and its folders, added with the system's folder picker and removed again. A folder belongs to one project at most.
- A session started in a project's folder, or below it, shows up under that project and its workspace. When two project folders hold it, the deepest one wins.
- Folder paths belong to this Mac and are never synced.
- Switching "Track time" off keeps the entries the project already has, and a note next to the switch says so.
- From phase 4, a project also names its issue tracker and the project or board there. A project without a tracker that keeps time never appears in time review.
- A workspace without projects works as in phase 1, and nothing asks for one.

### Rhythm

The focus presets: a name, the minutes of focus and of break, and a long break after a number of rounds. The app comes with 25 and 5, 50 and 10, and "none". A workspace names its default preset in Workspaces, and "Custom block" may choose another for one block. A preset that a workspace uses cannot be removed. This arrives in phase 2.

### Sessions

- **Claude Code profiles.** Each Claude account is its own profile folder. The app finds them, lists them with their path, and shows per profile whether its hook is installed, with an "Install hook" button. A profile can also be added by its folder.
- **Other agents.** Codex is listed as "added later".
- **Terminals.** iTerm2 and Terminal jump to the exact tab. VS Code and Cursor bring the window forward. Each shows whether macOS has allowed the app to control it, with an "Allow" button.

### Trackers

The issue trackers the user connected, Jira and Trello first, each with its account. The token goes to the Keychain. A project chooses its tracker under Workspaces. This arrives in phase 4.

## Sounds and notifications

- A soft chime when a focus interval ends (phase 2)
- A different chime when a break ends
- A longer tone when the block ends
- A short tick when an agent needs you, also with no block running, which can be muted during focus (phase 3)

### What phase 1 builds

Three alerts, each with a notification and a sound that can be switched off on their own:

| Alert | Sound | Notification | On by default |
|---|---|---|---|
| A block ends | Submarine | "Acme block finished", "Time to stop or start the next one." | Yes |
| A break ends | Glass | "Break is over", "Back to Acme." After a break with nothing running: "Break is over", "Start a block when you're ready." | Yes |
| 5 minutes before a block ends | Purr | "5 minutes left", "The Acme block ends soon." | No |

**Where the sounds come from.** They are the macOS system sounds in `/System/Library/Sounds`, played by name with `NSSound`. No sound file is in the repository, so no license is needed. The owner chose them. `AlertKind.soundName` in `Apps/Mac/AlertCenter.swift` records this.

How it works:

- The notifications are silent, because the app plays the sound itself. So the sound still plays when notifications are refused.
- Notifications are scheduled ahead and replaced on every change of plan: start, pause, resume, extend, break, switch and end. Their ids are `<bundle id>.<kind>`. Pending ones survive quitting the app.
- A paused block has no notification. A break cut off by the block's end gets only the block-end alert.
- A break with nothing running gets the break-end alert alone, with the same Settings switches and the same notification id. Its notification names no workspace.
- Ending, switching, pausing or ending a break by hand never plays a sound, and neither does a block start that ends a break with nothing running.
- A sound is skipped when it comes more than 60 seconds late, for example after the Mac slept.
- The rules live in `Alerts.swift` in `DontBurnCore` (`AlertKind`, `AlertSettings` and the plan).

**Permission.** It is asked at the first start of a block or a break, while macOS has not asked yet, and never at launch. While the system prompt is open, the compact panel shows one line under the actions. After a refusal only the note in Settings → General remains. When it is allowed later in System Settings, the app picks it up at the next change of plan.

**Settings → General** is a grouped form with three sections: When a block ends, When a break ends, and 5 minutes before a block ends. Each has a Notification switch and a "Sound (Name)" switch. The switches are stored in the defaults as `alert.<kind>.notification` and `alert.<kind>.sound`. When notifications are refused, a note says "Notifications are off for <app name>. Allow them in System Settings → Notifications." with an Open button, which only opens that pane. The version stays at the bottom, and the form scrolls when the note makes it taller than the window.

**Without notifications** the timer and the sounds work, nothing is scheduled, and Settings shows the way back.

## Which phase builds what

| Surface or part | Phase |
|---|---|
| Menu bar item: running, paused, break, nothing running | 1 |
| Compact panel: countdown, strip, four actions, quick start, custom block | 1 |
| Settings: Workspaces (name, color, default block, order, archive) | 1 |
| Window: Today as a list, simple history | 1 |
| Right-click menu: the block actions and the quick start items | 1 |
| Break gaps in the strip, "break in", Settings: Rhythm | 2 |
| Command bar, week and month charts, the idle question, start at login | 2 |
| Settings: the projects of a workspace, with their folders and the "Track time" switch | 3 |
| Needs-you strip, expanded panel, session switcher, Settings: Sessions, the amber badge, "Focus the waiting session" in the right-click menu | 3 |
| Issue on a block, a project's tracker, time review, Settings: Trackers | 4 |
| Day plan, next meeting, "free until", Out of office, the Off state, Settings: Calendars | 5 |
| iPhone pages and the Live Activity | 6 |

A part that belongs to a later phase is left out until then. It is not shown disabled.
