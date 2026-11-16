# Don't Burn Your Brain

A macOS menu bar app, with an iPhone companion later, for time blocks, tasks and agent terminal sessions across several workspaces. Swift 6, SwiftUI, SwiftData. Free and open source under the MIT license. Not sandboxed, and never on the App Store.

## Where things are

| Path | What it holds |
|---|---|
| `docs/spec/` | What to build: overview, features, feasibility, tech stack, design, plan, dev setup, decisions |
| `docs/design/prototype/index.html` | The drawn screens. Open it in a browser |
| `docs/process/` | How work is done here: agent flow, checks, tasks, safety and privacy |
| `Packages/DontBurnCore` | Shared logic and models, with tests |
| `Apps/Mac` | The menu bar app and Mac-only services |
| `Tools/dontburn-hook` | The hook CLI |
| `project.yml` | The XcodeGen definition. The Xcode project is generated and stays out of git |
| `rules/` | Rules for agents, one file per role (from card 3 on) |
| `.claude/` | The agent flow: subagents and commands (from card 2 on) |
| `.mcp.json` | The Trello MCP server. Only its address, never a token |

## Commands

Filled in when the Xcode project and the check command exist. Until then, see `docs/process/checks.md`.

- Generate the project: `xcodegen generate`
- Check everything before a push: `./scripts/check`
- Next card: `/next`. Start work on it: `/lead`. Merge: `/release`

## Rules that always apply

1. **Tasks are Trello cards.** The board is https://trello.com/b/nTimgmK2/dont-burn-your-brain, its lists are the statuses, and every step leaves a comment on the card. One card, one branch, one pull request. Read the card's `Blocked by` line before starting. Without access to the board, take the task from the chat. See `docs/process/tasks.md`.
2. **Nothing is done without proof.** The check command passes on the exact commit, and the commit carries its `local/check` status. A skipped test is not a pass.
3. **The owner merges by saying yes.** No agent merges, force-pushes or rewrites history on its own.
4. **Nothing personal in the repository.** No real employer, client, project or account names, no email addresses, no absolute home paths. Sample data is always Acme, Globex and Personal. See `docs/process/safety-and-privacy.md`.
5. **Be careful on the maintainer's Mac.** Stop only what you started, by process ID. Run only the development build, which keeps its data in its own folder. Never touch a Claude Code profile without the owner's yes.
6. **No GitHub Actions for tests.** Checks run locally. Workflows arrive with releases in phase 8.
7. **Every part works without the others.** Sessions, terminal focus, Jira, calendar, sync, the insight-flow integration and each terminal or agent adapter are optional layers on top of the timer. A part that is not set up, not installed or not permitted is left out of the interface, and nothing else breaks or nags. Every feature task says what the app does when its part is missing, and the Tester checks that case. The same holds for building and for the agent flow: a clone without Trello, the private notes or a signing team still builds, passes the check and runs the flow.
8. **Everything is written in English.** Code, comments, commits, pull requests, docs and Trello cards.
9. **The app only asks.** It never starts a timer, sends a worklog or changes another tool's settings by itself.

## Architecture rules

- Logic and models live in `DontBurnCore`, pure Swift, covered by tests. Views hold no business rules.
- Mac-only services (sessions, terminal focus, calendar) stay in `Apps/Mac`, each behind a small protocol, one adapter per agent tool and per terminal.
- Time is always passed in. Nothing in `DontBurnCore` reads the system clock directly, so tests never sleep.
- Secrets go to the Keychain. Never into the database, the defaults or a file.
- Interface text lives in the string catalog.
- Few dependencies. A new one is named in the task with its license and the reason.

## Data model rules, because of CloudKit

Sync arrives in phase 6, and the model has to be ready for it from the first version:

- Every property has a default value or is optional.
- Every relationship is optional and has an inverse.
- No unique constraints.
- After sync goes live, fields and models are only ever added.
- The store has an explicit path inside a folder named after the bundle identifier. Never the default location.

## Machine-specific notes

The maintainer keeps notes about his own Mac and accounts outside the repository, in a folder named `dont-burn-your-brain-handoff` next to this one. If it does not exist, you are not on his Mac and can ignore this. Nothing from that folder is ever copied here.
