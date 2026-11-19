# Decisions

What was decided before the first line of code, and what each decision changes. Add a row when a decision is made or changed, with the date, and correct the other spec files in the same pull request.

All rows below date from 15 November 2026, except those marked 16 Nov or 18 Nov. Text marked 17 Nov was corrected from the phase 0 spikes. Text marked 19 Nov was changed by the owner on a card.

| Topic | Decision | What it changes |
|---|---|---|
| **Technology** | Swift and SwiftUI, with one shared package for Mac and iPhone | No React Native, Tauri or Electron. Most of the hard parts are native macOS glue. See [tech-stack.md](tech-stack.md) |
| **OS versions** | The two latest major versions of macOS and iOS. Today that is 27 and 26 | The minimum target is version 26 on both. Current SwiftUI, SwiftData and menu bar APIs can be used without fallbacks. macOS 26 is the last version that runs on Intel Macs, so builds for other people stay universal |
| **Audience** | Not only the maintainer. Free and open source, and not in any App Store for now | A public repository, and the Mac app as a signed download that updates itself. Nothing is tied to one person's setup, there is a first-run setup, and adapters for more terminals and agents follow. This is phase 8 |
| **Release details** | MIT license. The repository is public from the first commit. Other people get the iPhone app through a TestFlight link | The license file is in the first commit, and every commit follows the privacy rules from the start. Adapters are built first for Claude Code, iTerm2, Terminal, VS Code, Cursor and Jira Cloud. Whether TestFlight is worth a fresh build every 90 days is looked at again in phase 8 |
| **Name and language** | Don't Burn Your Brain, as the working name. English interface first | The app carries this name on screen. Files, the repository and code use the short form DontBurn, without the apostrophe and the spaces. A quick search found nothing with exactly this name. The full check of the App Store, GitHub and trademarks happens before the repository becomes public |
| **Agents** | Claude Code first. Codex later | Sessions are read through one adapter per agent, so another agent is added without touching the rest |
| **Claude accounts** | Each Claude account is its own Claude Code profile folder | The app reads every profile folder and labels each session with its profile. It installs its hook once per settings file, and one settings file may be shared by several profiles. *17 Nov* More profiles can be added by path |
| **VS Code and Cursor** | Bringing the right window forward is enough | No companion extension for the exact terminal tab |
| **Time rules** | Round to 15 minutes. Breaks are logged too, with a switch to leave them out | Both rules live in each workspace, because two employers may want different ones: the rounding step, default 15 minutes, and whether breaks count, default yes. A break inside a block goes to the task of that block. Time between blocks is never counted |
| **Projects** | A workspace holds projects. Each project belongs to exactly one workspace and has a name, an order and an archived flag. *18 Nov* | Blocks and entries can name a project, and history totals per project. Projects get their screens and folders in phase 3 and an issue tracker in phase 4. See [tech-stack.md](tech-stack.md) |
| **Time tracking is per project** | A project's time can be switched off from tracking. *18 Nov* | A block or entry may name only a tracked project of its own workspace. The rule is checked when the project is assigned |
| **Sleep and quit** | When the Mac sleeps or the app quits during a block, the block still ends at its planned time, and the time in between counts as worked. *18 Nov* | After a restart, an overdue entry and block close at the planned end. Idle detection in phase 2 refines this. See [features.md](features.md) |
| **Jira** | Jira Cloud with native worklogs. An assumption, not something that was checked | Phase 4 starts by finding out, in each organization, whether time is logged through Tempo. If it is, Tempo becomes a second provider |
| **Calendar** | Meetings are read from the calendar the Mac already keeps, through EventKit | Confirmed with one company Google account: once the account is added in System Settings with Calendars on, its meetings are there. One permission prompt, no Google sign-in in the app. macOS fetches a Google account every 15 minutes, so a recent change can be missing. The Google Calendar API stays plan B for an account whose admin blocks this route |
| **Meetings and days off** | Meetings that were not answered still count. Out of office means out of office | Every meeting counts unless it was declined. An Out of office entry is never time worked: it marks the workspace whose calendar it is in as off, its meetings are not counted and nothing reminds the user. When nothing else is planned, the whole day is off and the menu bar says so. It arrives as a timed entry with nothing proven to mark it, so the app goes by its name, from a short list the user can edit |
| **Planning** | Plan the whole day. When a planned block is due, the app only asks and never starts it by itself | The Day plan feature, built together with the calendar in phase 5 |
| **Panel and shortcuts** | The Mac gets the wide expanded panel, the iPhone gets pages. Quick actions are Pause, Break, +15 and Switch. Global shortcuts are ⌥ Space and ⌥ Tab | End block lives in the right-click menu and the command bar. *19 Nov* It is also in the compact panel, as a quieter row under the four quick actions, with the E key. This is the owner's decision on card 43. Both shortcuts can be changed in Settings if they clash |
| **insight-flow in the app** | The app's integration only reads. This is a product feature for people who use insight-flow, planned for phase 7 | It asks the CLI for the current task (`insight-flow current` prints JSON with the id, title and status) and watches `.taskflow-activity.jsonl` for changes. insight-flow itself needs no change. It plays its own alert sounds, so alerts get a per-project switch |
| **Apple Developer Program** | Not joined yet | Needed for iCloud sync, TestFlight and notarized builds, even though the app is free. Join when the first build goes to another person or when sync starts, whichever comes first. Until then everything runs from Xcode |
| **Tasks** | Tasks are cards on the maintainer's Trello board, read and moved through Trello's official MCP server. The lists are the statuses. insight-flow is not used to build this project. *16 Nov* | Every step leaves a comment on its card. The board also works without the agent flow, and the flow works without the board. GitHub Issues become the inbox for other people in phase 8. See [../process/tasks.md](../process/tasks.md) |
| **Checks** | Tests and everything else run locally. GitHub runs only releases. No self-hosted runner for now | One check command, a git hook before every push, and a commit status as proof. See [../process/checks.md](../process/checks.md) |
| **Agent flow** | A Leader, five roles and a Release master, following the maintainer's reference flow | Built in card 2 from Claude Code's own subagents and skills. See [../process/agent-flow.md](../process/agent-flow.md) |
| **Every part works alone** | Other people will not have everything set up the way the maintainer has. Each part works without the others | The timer needs nothing else. Sessions, terminal focus, Jira, calendar, sync and insight-flow are optional layers: a part that is missing, not installed or not permitted is left out of the interface and nothing else breaks. Each feature task names its missing case, and the Tester checks it. Building from a fresh clone needs only Xcode and the four command line tools |
| **Repository** | Public from the first commit, under the maintainer's personal GitHub account. *16 Nov* | Privacy rules hold from commit one. Rulesets are available, so `main` can require the local check. GitHub's own runners are free for public repositories, but checks stay local for now |
| **Language** | Everything written is in English. *16 Nov* | Code, comments, commits, pull requests, docs and Trello cards |
| **Privacy in the repository** | Nothing personal enters the repository. Sample data is Acme, Globex and Personal | A privacy scan in the check command, and rules that hold from the first commit. See [../../rules/safety-and-privacy.md](../../rules/safety-and-privacy.md) |

## Still assumptions

Each of these has a moment when it gets checked.

| Assumption | Checked |
|---|---|
| Both organizations use Jira Cloud with native worklogs | When phase 4 starts |
| ⌥ Space and ⌥ Tab are free as global shortcuts | In phase 2, when the command bar is built |
| macOS passes along nothing that marks an Out of office entry | In phase 5 |
| The app can ask macOS for a fresh fetch of a calendar account | In phase 5 |
| iCloud sync behaves in a signed, notarized build the way it does from Xcode | Early in phase 6 |

Checked and taken out of the table:

- "A hook can tell which terminal tab it runs in, on all four terminal hosts." Checked in the phase 0 spikes. *17 Nov* Yes in Terminal and iTerm2. In VS Code and Cursor the hook names the editor, but not the tab. Reasoned, not seen: a container session names neither the editor nor a folder on the Mac. See [../spikes/phase-0.md](../spikes/phase-0.md).

## What free, open source and no App Store means in practice

- The Mac app is not affected. It could never go to the Mac App Store, and a signed download from the project page is the normal route for a tool like this.
- The Apple Developer Program fee of 99 USD a year still applies. Signing, notarization, iCloud sync and TestFlight all need it, for a free app too.
- The iPhone app can reach other people only through a TestFlight link: up to 10,000 testers, one review of the first build, and every build stops working after 90 days, so a fresh one has to go up at least that often.
- Someone who builds the app from source gets everything except sync, unless they sign it with their own paid Apple developer account. The iCloud container belongs to the account that signs the build.
