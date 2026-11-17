# The agent flow

How a task moves through this repository when agents do most of the work. It is built only from what Claude Code itself offers: subagents and skills in `.claude/`. Tasks are cards on the maintainer's Trello board, and the board's lists are the statuses.

The design follows a flow the maintainer already runs in another project, called the reference flow here, cut down for one repository and one Mac app.

## How it is built

| Path | What it holds |
|---|---|
| `.claude/agents/` | Five subagents: `developer`, `designer`, `tester`, `reviewer`, `documenter`. Each is short and sends the agent to `rules/README.md` and its role file. Each has a fixed set of tools: none of them has the Trello tools or can start another agent, and the Reviewer has no editing tools |
| `.claude/skills/` | The commands the owner types: `/lead`, `/release`, `/next`, `/review`, `/design`. Only a person can start them |
| `rules/README.md` | What every agent reads first: the list of rule files and who reads each, the result line, the card comments, where the work happens |
| `rules/*.md` | The general rules: code style, testing, git, safety and privacy, releases, the definition of done and the lessons |
| `rules/roles/` | One file per role: what it does, what it may touch, how it reports |
| `.worktrees/` | One git worktree per card, made from a fresh `origin/main`. Also a takeover's own worktree under `takeover/`, and the Tester's screenshots under `screenshots/`, which stay local. Ignored by git |

`/lead` and `/release` run in the main session, because they talk to the owner, move cards and call the subagents. `/review` and `/design` run the Reviewer or the Designer alone, as a forked subagent. `/next` only reads the board.

Every card is worked on in its own worktree, `.worktrees/<branch>`, so the main checkout stays as it is and two cards never share a working tree. A Leader that takes over a stopped session's card works in a worktree of its own instead, as [../../rules/roles/leader.md](../../rules/roles/leader.md) says under "Taking over". The rules are always read from the main checkout.

## The idea

The owner talks to one agent, the Leader. The Leader runs a small team of roles that cannot do each other's job. A separate Release master asks the owner for one yes before anything is merged. Every step leaves a comment on the card, so the board shows what happened without opening a terminal.

## Roles

| Role | Started with | Does | Never does |
|---|---|---|---|
| **Leader** | `/lead`, in the main session | Takes the owner's request or the next card, checks it against `docs/spec`, writes the brief, calls the subagents, checks every claim before trusting it, moves the card and comments on it | Edits code, tests or docs |
| **Developer** | The Leader, as the `developer` subagent | Logic, data and services in Swift. Opens the pull request | Writes tests. Changes how a view looks beyond wiring it up |
| **Designer** | The Leader as the `designer` subagent, or `/design` | The look of the SwiftUI views, held against `docs/spec/design.md` and the prototype | Writes logic |
| **Tester** | The Leader, as the `tester` subagent | Builds and starts the development build, checks the done-when list by hand, then writes the tests. A card that changes nothing in the app is checked as its "How to verify" says instead. Posts a verdict. When a screen changed, takes screenshots that stay on the Mac | Changes product code |
| **Reviewer** | The Leader as the `reviewer` subagent, or `/review <PR>` | Reads code and tests. Privacy and what the app does on the user's Mac come first. Posts a verdict | Changes anything |
| **Documenter** | The Leader, as the `documenter` subagent | Keeps `docs/` in step when behaviour changed, or notes that nothing needed changing | Changes code |
| **Release master** | `/release`, in the main session | Goes through the second checklist of the definition of done on the latest commit, asks the owner for one yes, merges, moves the card to Done | Merges without the yes. Fixes things |

The Leader and the Release master run in the main session, because they talk to the owner and call the subagents. Only these two move cards and write on the board. Subagents report to the Leader.

The roles cannot do each other's job: only the Tester writes tests, only the Developer and the Designer change product code, and the Reviewer edits nothing. What each role may touch is in its file in [../../rules/roles/](../../rules/roles/).

## The path of one task

1. **Leader.** Picks the card (`/next` shows which one and why), writes the brief from the card and the spec, and asks the owner only what they leave open. Checks the card's `Blocked by` line and the open pull requests that touch the same files.
2. **Developer or Designer.** Works on the card's branch, in its worktree made from a fresh `origin/main`, and opens the pull request.
3. **Tester.** `APPROVE:` or `REJECTED:` on the pull request. When a screen changed, the Tester takes screenshots in light and dark. They are never committed or uploaded: the Leader shows them to the owner. See "Checking a screen" in [../../rules/testing.md](../../rules/testing.md).
4. **Reviewer.** `APPROVE:` or `REJECTED:`. A serious finding sends the task back.
5. **Documenter.** Docs updated in the same pull request, or a note that none are needed.
6. **Release master.** The owner's yes, then the merge.

After three failed rounds of testing or review, the Leader moves the card to Needs decision and asks the owner.

Every step ends with a comment on the card. Its form, and what never goes into one, are in [../../rules/README.md](../../rules/README.md) under "Comments on the card".

## Statuses

Each status is a list on the Trello board, in this order. Moving a card is how its status changes.

| List | Meaning | Moved there by |
|---|---|---|
| Backlog | Written, not ready to start yet | The owner or the Leader |
| Ready | Can be pulled. The top card whose blockers are all in Done goes next | The owner or the Leader |
| In design | The Designer is working | Leader |
| In development | The Developer is working | Leader |
| In testing | The Tester is checking | Leader |
| In review | The Reviewer is reading | Leader |
| Changes requested | The Tester or the Reviewer rejected it | Leader |
| In docs | The Documenter is working | Leader |
| Needs decision | Waiting for the owner: a question, or three failed rounds | Leader |
| Ready to merge | Everything passed. Waiting for the Release master | Leader |
| Merge blocked | The Release master found a problem on the latest commit | Release master |
| Done | Merged | Release master |
| Cancelled | Dropped, with the reason in a comment | Leader |

A typo in a list name breaks the flow quietly. The Leader reads the board's lists at the start and stops if one is missing.

## The result line

Every role the Leader calls ends its last message with one `RESULT:` line. The Leader reads it first, then checks the claim before it moves the task on. The exact form is in [../../rules/README.md](../../rules/README.md).

## Verdicts

All agents act through one GitHub account, so none of them can approve a pull request. The Tester and the Reviewer post a verdict as a comment instead, `APPROVE:` or `REJECTED:`, and it belongs to the commit it names. The format, and when a verdict still counts for a later head commit, are in [../../rules/git.md](../../rules/git.md) under "Verdicts".

## Definition of done

It is in [../../rules/definition-of-done.md](../../rules/definition-of-done.md), as two checklists. The Leader goes through the first before a card moves to Ready to merge. The Release master goes through the second before the merge, on the latest commit, and it ends with the owner's yes.

## Spikes

A spike answers a question instead of delivering a feature. It follows the same order, with a lighter test and a note in `docs/spikes/` as what gets delivered. The differences are in [../../rules/roles/leader.md](../../rules/roles/leader.md) under "Spikes".

## Dependencies between cards

Every card carries two lines in its description, `Blocked by:` and `Blocks:`, with card numbers such as `#5`, or `none`. The Leader reads them before it starts a card. What it does with a blocked card is in [../../rules/roles/leader.md](../../rules/roles/leader.md).

## Working without the board

Someone who clones this repository has no access to the maintainer's Trello board, and the Trello server may simply not be connected. The flow still works: `/lead <the task in words>` takes the task from the chat, reports each status in its replies instead of moving a card, and everything else stays the same. `/release` then takes the pull request number. `/next` says that it cannot read a board.

## Lessons

[../../rules/lessons.md](../../rules/lessons.md) holds what went wrong before and the rule that came from it. It starts with the lessons carried over from the reference flow. The Leader reads it at the start of every card and proposes an entry to the owner after a bad outcome. An entry is a task of its own, apart from the card it came from. When an entry is written, where it is committed, its format and the three statuses are in that file.

## Who may change the agents and the rules

That is said in [../../rules/README.md](../../rules/README.md) under "Who changes the rules", with the paths it covers, and how a change is made is in [../../rules/roles/leader.md](../../rules/roles/leader.md) under "Changing the flow". The owner is asked twice: before the change is written and again at the merge.

## Not part of the flow yet

- GitHub issues. They arrive in phase 8, when other people start to report things, and each accepted one becomes a card.
- Any role beyond the seven above.
- Automation outside Claude Code: no Trello Power-Ups, no webhooks, no scripts that move cards.
