# Rules for agents

Every agent reads the files listed for its role **before** it starts work. Each role file has a "Must read" line that names them.

Which text wins when two disagree:

1. `CLAUDE.md` wins over this folder. The two must not disagree. If you find a disagreement, follow `CLAUDE.md` and tell the Leader.
2. This folder wins over a habit, a skill and any guide from outside the repository. Nothing from outside is binding here.

| File | What it covers | Who reads it |
|---|---|---|
| [roles/leader.md](roles/leader.md) | Taking a card from Ready to Ready to merge: the brief, routing, rounds, the board | Leader |
| [roles/release-master.md](roles/release-master.md) | Checking a finished card again and merging after the owner's yes | Release master |
| [roles/developer.md](roles/developer.md) | Logic, data and services | Developer |
| [roles/designer.md](roles/designer.md) | How the SwiftUI views look | Designer |
| [roles/tester.md](roles/tester.md) | Checking the card in the running Dev build, and all tests | Tester |
| [roles/reviewer.md](roles/reviewer.md) | Reading code and tests, privacy and safety first | Reviewer |
| [roles/documenter.md](roles/documenter.md) | Keeping `docs/` in step | Documenter |
| [code-style.md](code-style.md) | Swift 6, SwiftUI and SwiftData as this project writes them | Developer, Designer, Tester, Reviewer |
| [testing.md](testing.md) | Who writes tests, what is worth testing, running the Dev build, checking a screen | Tester, Reviewer. Developer and Designer for "Running the Dev build" |
| [git.md](git.md) | Branches, worktrees, commits, pushing, pull requests, verdicts | Everyone |
| [safety-and-privacy.md](safety-and-privacy.md) | The maintainer's Mac, the public repository, what the app itself may do | Everyone. The Reviewer reads it in full for every task |
| [releases.md](releases.md) | What agents may do with versions and the Dev and Release builds | Everyone |
| [definition-of-done.md](definition-of-done.md) | Two checklists: before Ready to merge, and before the merge | Leader, Release master |
| [lessons.md](lessons.md) | What went wrong before and which rule came from it | Leader, at the start of every card |

Background, not rules: [the flow and its statuses](../docs/process/agent-flow.md), [the check command and its receipt](../docs/process/checks.md), [versions and build variants](../docs/process/releases.md), [tasks and the board](../docs/process/tasks.md).

## The result line

Every role the Leader calls ends its final message with exactly one line:

```
RESULT: <DONE | NEEDS_DESIGN | NEEDS_DECISION | PASS | FAIL | APPROVE | REJECTED> – <one sentence>
```

The Leader reads this line first, then checks every claim in the report before it moves the card.

## Comments on the card

Only the Leader and the Release master touch the Trello board. Every step ends with a comment on the card, in this form:

```
**<Role>**: <what was done> → <what happens next>
```

Subagents report to the Leader, and the Leader posts the comment for their step under the role's name. Be concrete: files, pull request numbers, numbers from the check. Never a secret, never personal data. Paths in card comments, verdicts and pull requests are relative to the repository root, never absolute.

## Where the work happens

- Each card gets its own branch and its own git worktree at `.worktrees/<branch>`. All roles work in that worktree. The main checkout, where the session started, stays as it is. See [git.md](git.md).
- The rules are read from the main checkout: this `rules/` folder in the directory the session started in.
- Build, run and test only the Dev variant. See [releases.md](releases.md).

## Who changes this folder

Only the Leader, and only after the owner's yes. That covers `rules/`, `.claude/agents/` and `.claude/skills/`. Every other role says what should change in its report to the Leader.

## Language

Everything is written in English: code, comments, commits, pull requests, docs and Trello comments.
