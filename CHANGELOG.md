# Changelog

What changed in each version of Don't Burn Your Brain, written for the people who use it. Versions follow [docs/process/releases.md](docs/process/releases.md).

## 0.2.0

A rhythm of focus and breaks, a question about time away from the Mac, history by week and month, and a command bar.

### Added

- **Focus rhythm.** A block can follow a preset of focus intervals and breaks. The app comes with 25/5, with a 15-minute long break after 4 rounds, and 50/10. No workspace has one until you choose it, so blocks run as before.
- **Rhythm tab** in Settings: create, change and remove presets, with focus and break minutes, an optional long break after a number of rounds, and whether the block resumes by itself after a break or waits for you. A preset that a workspace uses can't be removed. Each workspace picks a default rhythm in Workspaces, and the custom block (⌘N) can choose another one, or none.
- **The rhythm in the panel.** The strip shows the breaks as gaps, and the line under the countdown says "break in 19 min". When a planned break is due, Break reads "Break now" and starts it at its planned length. Nothing starts by itself: a due break left alone for its length is skipped.
- **The focus-end alert**, a sound and a notification when a focus interval ends and a break is due. It has its own switches in Settings, General, on by default.
- **Choose a break's length.** Break opens "Break for", with 5, 15, 30 and 60 minutes on the keys 1 to 4. The length used last is preselected for Return. In the right-click menu, "Take a break" is a submenu with the same lengths.
- **A break with nothing running**, such as lunch, from "Take a break" in the panel or the right-click menu. It counts toward no total, and its end has the break-end alert.
- **End block in the panel**, a row under the four actions, also on the E key.
- **Time away from the Mac.** After 10 minutes without input, or a sleep, during a block, the app asks on your return what that time was: Work, Meeting, Break or Discard. The question waits at the top of the panel, and a notification says so when notifications are allowed. Nothing opens by itself, and no permission is needed. Settings, General switches it off or changes the minutes.
- **History by week and month.** A Day, Week and Month switch, a bar chart per day or week stacked by workspace, and a table of work, breaks and totals. A click on a bar opens that day or week. The sidebar shows last week's totals per workspace. Weeks start on the first weekday your Mac is set to.
- **Split an entry** at a whole minute, from its context menu on Today and in History. No minute is lost.
- **Export…** saves the shown day, week or month as a CSV file that spreadsheets open with accented letters intact.
- **Command bar**, opened from any app with ⌥ Space, or with "Open the command bar" in the right-click menu. Type a workspace and a length, such as `ac 2h`, or `pause`, `break 10`, `+15` or `end`, and press Return. With the field empty, 1 to 3 start your first three workspaces.
- **Shortcuts tab** in Settings: change the command bar's shortcut or switch it off. It says when macOS or another app already uses the keys.
- **Start at login**, a switch in Settings, General. It adds the app to the login items that System Settings, Login Items lists.
- **Projects** in Settings, Workspaces: a Workspace | Projects switch, and per project a name, a "Track time" switch and its folders on this Mac. Folder paths never leave this Mac. Nothing gives a block or an entry a project yet. Projects are there for the session list.
- **Sessions tab** in Settings: it lists your Claude Code profiles, installs the hook into a profile's settings file after showing the exact lines that change, and removes exactly its own lines again. When nothing else changed the file in between, it is byte for byte what it was. Otherwise the app says what differs and keeps the backup. With the hook installed, `dontburn-hook` reports each session's events to the running app.
- **VoiceOver opens the right-click menu** with the menu bar item's "Show menu" action.

### Changed

- **Break asks for the length first**, instead of starting 5 minutes at once, unless a planned break is due.
- **+15 minutes on a break** adds to the break too, so the work left after it stays the same.

### Fixed

- For people who build the app: an incremental Debug build could lose its variant and run as Release.

### Notes

- **Your data moves over by itself.** On its first start, 0.2.0 migrates the store of 0.1.0, and every workspace and entry stays. Before it puts the new app in place, `./scripts/install-release` now copies the store files aside, next to the data folder in `~/Library/Application Support`, into a new folder named after the bundle identifier with `.backup-`, the date and the time, such as `io.github.slavo775.dontburn.backup-2026-12-01-093000`. It prints where, and never removes a backup: delete one yourself once you no longer need it.
- **The session list is not in this version yet.** The hook can be installed and the app records the sessions, but the panel lists them only in a later version.
- **In the Release build, the command bar's shortcut ⌥ Space is on from the first start.** Change it or switch it off in Settings, Shortcuts. While it is on, other apps can't type the non-breaking space that ⌥ Space gives. **Start at login is off** until you switch it on. The Dev build turns on neither by default.
- Everything stays on your Mac. There is no sync, no network access and no telemetry yet.
- Without a Personal Team in `Local.xcconfig`, the app is signed to run locally, and macOS may ask for its permissions again after each update.

## 0.1.0

The first version for a whole working day: time blocks per workspace, run from the menu bar.

### Added

- **Menu bar countdown.** The item shows the running block's workspace dot, name and time left, "paused" while paused, a cup and the time left on a break, and an outline dot when nothing runs. After 15 minutes with nothing running it shows how long nothing has been tracked.
- **Compact panel.** A click on the item opens a panel with the running block, its countdown and four quick actions: Pause, Break, +15 minutes and Switch, also on the keys P, B, + and S. Escape closes it.
- **Quick start.** With nothing running, the panel lists your workspaces on the keys 1 to 9 and offers a custom block on ⌘N, with today's tracked total below.
- **Right-click menu** on the item: pause or resume, take a break, add 15 minutes, end the block, start one of your first three workspaces, open the window, Settings and Quit.
- **Workspaces** in Settings: create, rename, recolor, reorder by dragging, archive and restore, each with its default block length.
- **Today and history window**, opened with ⌘O: a day's entries with totals per workspace and for the day. Entries can be corrected, added and deleted by hand, and earlier days are under History.
- **Sounds and notifications** when a block or a break ends, and an optional warning five minutes before a block ends. Each has its own switches in Settings, General. The app asks for the permission when you first start a block, never at launch.
- **Settings, General shows what is running:** version, build and variant.
- **The Dev build and the daily copy live side by side.** They have separate data, settings and permissions. The Dev build has a tinted icon and "DEV" in its menu bar item.
- **`./scripts/install-release`** builds the daily copy from a clean `main` and installs it in `/Applications`.
- **`dontburn-hook`**, the command-line tool for agent hooks, prints its version and build. It does nothing else yet.

### Notes

- Everything stays on your Mac. There is no sync, no network access and no telemetry yet.
- Without a Personal Team in `Local.xcconfig`, the app is signed to run locally, and macOS may ask for its permissions again after each update.
