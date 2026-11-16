# Don't Burn Your Brain

One menu bar for time, tasks and agent terminals.

A macOS app, with an iPhone companion later, for people who work across several organizations with many AI agent sessions open at once. You commit a block of time to one workspace, see which agent sessions belong to it and jump to the right terminal in one click, and end the day with hours ready to log to Jira.

**Status: early.** Nothing here is usable yet. The plan is in [docs/spec/plan.md](docs/spec/plan.md).

## What it will do

- Time blocks per workspace, with a countdown in the menu bar, breaks and a history
- A live list of Claude Code sessions, with a button that brings the right terminal tab forward
- Jira worklogs from tracked time, after a review where every number can still be changed
- Meetings from the calendars the Mac already keeps, and a plan for the day around them
- The same data on the iPhone through iCloud

The full description is in [docs/spec](docs/spec), and the drawn screens are in [docs/design/prototype](docs/design/prototype).

## Build

Written when the Xcode project exists.

## How work is done here

Most of the code is written by AI agents and reviewed by a person. [docs/process](docs/process) describes the agent flow, the local checks and the rules for safety and privacy.

## License

MIT. See [LICENSE](LICENSE).
