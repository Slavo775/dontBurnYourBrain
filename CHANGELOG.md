# Changelog

What changed in each version of Don't Burn Your Brain, written for the people who use it. Versions follow [docs/process/releases.md](docs/process/releases.md).

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
