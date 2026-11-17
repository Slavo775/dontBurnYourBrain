# Safety and privacy

Three sets of rules: what agents may do on the maintainer's Mac, what never enters this repository, and what the app itself may do on a user's Mac. The Reviewer reads this file in full for every task.

## On the maintainer's Mac

The Mac the agents work on is the one the maintainer uses every day, for more than one employer. Treat it that way.

**Processes**

- Stop only the processes you started, by the process ID you recorded. Never `pkill -f`, `killall` or another name pattern.
- Never `sudo`.

**Builds and data**

- Run only the Dev build. It has its own bundle identifier, its own data folder, its own settings and its own permissions. See [releases.md](releases.md).
- Never open, copy or change the data of the copy the maintainer uses daily.
- Anything that deletes or rewrites data runs against a throwaway store: in memory, or in a temporary folder that is removed afterwards.
- Screenshots come from the Dev build with the seeded sample data.

**Claude Code profiles and other tools**

- The maintainer's Claude Code profile folders are off limits. Do not list them, read them or write to them unless the task says so and he has said yes in this session.
- Hook experiments start in a scratch project, through that project's own settings file. A real profile is changed only after his yes, one profile at a time, with a backup of the settings file and an uninstall that has been tested.
- When a profile's settings file is changed: add only this app's own entries, keep every other key and its formatting, and prove that uninstalling leaves the file identical to the backup.
- Before changing a profile's settings file, check whether it is a symlink. If it is, stop and name the file it points to. Several profiles can share one file, so the maintainer's yes must name the file that is really written.
- Session transcripts hold other people's work. Read structure, never copy content, and never into this repository.
- Other repositories on the Mac are read-only.

**Permissions and the system**

- macOS permission prompts (Automation, Accessibility, Calendars, Notifications) are answered by the maintainer. Say that a prompt is coming and why.
- Never reset permissions, change System Settings or edit login items.
- AppleScript that drives a terminal or an editor runs only in the tasks that are about it.
- Type by script only into a tab or window you opened yourself. Send the text, check the input line through the terminal's own AppleScript, then send Return on its own. Terminal's `do script` always adds Return, so never send a slash command with it. An unexpected menu or dialog gets Escape and a report, never a choice.
- An AppleScript call that fails with error −1712 means a dialog is open on screen. Retry once, then stop and report it.

**Git**

The rules about a dirty working tree, other sessions' worktrees, hooks and history are in [git.md](git.md).

## In the repository

The repository is public, and git keeps everything. Every push can be read by anyone at once. So nothing personal goes in.

**Never in code, docs, tests, fixtures, screenshots, task files, commit messages or pull requests:**

- names of the maintainer's employers or clients, their projects, repositories or issue keys
- account names, profile names and email addresses, except GitHub's noreply address in commit metadata
- absolute paths with a user name. Write `~` for the home folder
- anything read from a session transcript, a calendar or Jira
- tokens, keys and passwords, in any form

Trello cards and their comments follow the same rules, because the board may be shared later.

**Sample data** is always the same neutral set: the workspaces Acme, Globex and Personal, issue keys such as `ACM-412` and `GLX-88`, folders such as `~/code/acme-web`. Previews, tests, screenshots and recordings use only this set, loaded by a launch argument.

**The privacy scan** is part of the check command. It reads a list of patterns from a file outside the repository and fails when any of them appears in a tracked file. It also fails on an email address, an absolute home path, and a new commit without a noreply address. On a machine without the list, the word check is skipped and says so.

**Dependencies.** A new dependency is named on the card with its license and the reason, and the Reviewer checks both. Sounds, icons and fonts need a license that fits an MIT project, recorded next to the file.

**A secret that was found** is never repeated. Name the file and the line, and say it must be rotated.

## What the app itself may do

These are product rules. A change that breaks one of them needs the owner's decision, not just a review.

- **Local first.** The app works fully offline. Its data stays on the user's devices and in the user's own iCloud. There is no server and no telemetry.
- **Network.** It talks only to the Jira sites the user added and to iCloud. Nothing else, ever, without a decision recorded in `docs/spec/decisions.md`.
- **Secrets** live in the Keychain. Never in the database, the defaults, a file or a log.
- **It only asks.** The app never starts a timer by itself, never sends a worklog without showing it first, never changes another tool's settings by itself, and never installs a hook without consent.
- **Hooks are reversible.** Installing adds the app's own entries to a profile's settings and nothing else. Uninstalling removes exactly those.
- **Transcripts are read, not kept.** The app reads a session's title and last activity from disk. It does not copy transcript content into its own store, and nothing from a transcript is synced.
- **Input from outside is checked.** Every way into the app from outside (the hook's event channel, a URL scheme, a watched file) limits the size and checks the shape of what it reads before acting on it.
- **Permissions one at a time**, each asked when it is first needed, with the reason.
- **Logs** hold no issue titles, no meeting titles, no paths inside a user's projects and no tokens.
