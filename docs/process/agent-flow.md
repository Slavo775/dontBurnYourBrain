# The agent flow

How a task moves through this repository when agents do most of the work. It is built only from what Claude Code itself offers: subagents and commands in `.claude/`. Tasks are cards on the maintainer's Trello board, and the board's lists are the statuses. Card 2 builds the flow, and this file is then corrected to match what was built. Until then it is the design.

The design follows a flow the maintainer already runs in another project, called the reference flow here, cut down for one repository and one Mac app.

## The idea

The owner talks to one agent, the Leader. The Leader runs a small team of roles that cannot do each other's job. A separate Release master asks the owner for one yes before anything is merged. Every step leaves a comment on the card, so the board shows what happened without opening a terminal.

## Roles

| Role | Started with | Does | Never does |
|---|---|---|---|
| **Leader** | `/lead`, in the main session | Takes the owner's request or the next card, checks it against `docs/spec`, writes the brief, calls the subagents, checks every claim before trusting it, moves the card and comments on it | Edits code, tests or docs |
| **Developer** | The Leader, as a subagent | Logic, data and services in Swift. Opens the pull request | Writes tests. Changes how a view looks beyond wiring it up |
| **Designer** | The Leader as a subagent, or `/design` | The look of the SwiftUI views, held against `docs/spec/design.md` and the prototype | Writes logic |
| **Tester** | The Leader, as a subagent | Builds and starts the development build, checks the done-when line by hand, then writes the tests. Posts a verdict with screenshots when a screen changed | Changes product code |
| **Reviewer** | The Leader as a subagent, or `/review` | Reads code and tests. Privacy and what the app does on the user's Mac come first. Posts a verdict | Changes anything |
| **Documenter** | The Leader, as a subagent | Keeps `docs/` in step when behaviour changed, or notes that nothing needed changing | Changes code |
| **Release master** | `/release`, in the main session | Goes through the whole definition of done again on the latest commit, asks the owner for one yes, merges, moves the card to Done | Merges without the yes. Fixes things |

The Leader and the Release master run in the main session, because a subagent cannot start other subagents. Only these two move cards and write on the board. Subagents report to the Leader.

Nobody but the Tester writes tests. Nobody but the Developer and the Designer changes product code. The Reviewer edits nothing.

## The path of one task

1. **Leader.** Picks the card (`/next` shows which one and why), writes the brief from the card and the spec, and asks the owner only what they leave open. Checks the card's `Blocked by` line and the open pull requests that touch the same files.
2. **Developer or Designer.** Works on a branch from a fresh `main` and opens the pull request.
3. **Tester.** `APPROVE:` or `REJECTED:` on the pull request, with screenshots in light and dark when a screen changed.
4. **Reviewer.** `APPROVE:` or `REJECTED:`. A serious finding sends the task back.
5. **Documenter.** Docs updated in the same pull request, or a note that none are needed.
6. **Release master.** The owner's yes, then the merge.

After three failed rounds of testing or review, the Leader moves the card to Needs decision and asks the owner.

Every step ends with a comment on the card:

```
**<Role>**: <what was done> → <what happens next>
```

Concrete: files, pull request numbers, numbers from the check. No secrets, no personal data, nothing from the maintainer's real calendar or Jira.

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

Every role the Leader calls ends its last message with exactly one line:

```
RESULT: <DONE | NEEDS_DESIGN | NEEDS_DECISION | PASS | FAIL | APPROVE | REJECTED> – <one sentence>
```

The Leader reads this line first, then checks the claim: it looks at the pull request, the commit status or the file itself before it moves the task on.

## Verdicts

All agents act through one GitHub account, so none of them can approve a pull request. A verdict is a comment on the pull request:

```
APPROVE: <short reason>
REJECTED: <short reason>
- <finding with file:line>
```

Only the Tester and the Reviewer post verdicts. A verdict belongs to the commit it was given on. A later commit that changes product code or tests needs a new one.

## Definition of done

A card may move to Ready to merge only when all of this is true:

- The done-when list on the card is met, shown by evidence from this session.
- `./scripts/check` passed on the head commit of the pull request, and that commit carries the `local/check` status.
- The Tester posted `APPROVE:`: checked in the running development build, with screenshots in light and dark when a screen changed, and tests added or updated.
- The Reviewer posted `APPROVE:`, with no open serious finding on privacy, on safety or on security.
- Docs are updated in the same pull request, or the Documenter noted why none are needed.
- The privacy scan is clean: nothing personal in code, docs, screenshots or commit messages.
- No more than three failed rounds. Otherwise the card went to Needs decision and the owner decided.
- The card has a comment for every step, and links the pull request.

Before merging, the Release master checks all of it again on the latest commit, runs the check command once more, and needs the owner's yes from this session.

Card 3 turns this section into `rules/definition-of-done.md`.

## Spikes

A spike answers a question instead of delivering a feature. It follows the same order with two differences: the Tester only repeats the result and confirms the numbers, and the Documenter's note in `docs/spikes/` is what gets delivered. Spike code stays out of the app target.

## Dependencies between cards

Every card carries two lines in its description, `Blocked by:` and `Blocks:`, with card numbers such as `#5`, or `none`. The Leader reads them and does not start a card whose blockers are not in Done.

## Working without the board

Someone who clones this repository has no access to the maintainer's Trello board, and the Trello server may simply not be connected. The flow still works: `/lead` takes the task from what the person writes in the chat, reports each status in its replies instead of moving a card, and everything else stays the same.

## Lessons

`rules/lessons.md` is written by the Leader after a bad outcome: two or more failed rounds, a decision the owner corrected, a blocked merge, a cancelled task. Each entry says what happened, the root cause and the proposed change, with a status: `proposed`, then `accepted` or `declined`. Nothing in a rule or an agent changes without the owner's yes. Accepted lessons are binding.

The file starts with lessons carried over from the reference flow.

## Who may change the agents and the rules

Only the Leader, and only after the owner's yes. That covers `.claude/agents/`, the commands and `rules/`. Every other role says what should change in its report to the Leader.

## Not part of the flow yet

- GitHub issues. They arrive in phase 8, when other people start to report things, and each accepted one becomes a card.
- Any role beyond the seven above.
- Automation outside Claude Code: no Trello Power-Ups, no webhooks, no scripts that move cards.
