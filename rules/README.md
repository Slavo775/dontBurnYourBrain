# Rules for agents

Every agent reads the files listed for its role **before** it starts work. A rule here wins over a habit. A rule in `CLAUDE.md` wins over this folder, and the two must not disagree.

This is the minimum the agent flow needs to run. Card 3 adds code style, testing, git, safety and privacy, the definition of done, releases and lessons. Until then, the documents named below are binding as they stand.

| File | What it covers | Who reads it |
|---|---|---|
| [roles/leader.md](roles/leader.md) | Taking a card from Ready to Ready to merge: the brief, routing, rounds, the board | Leader |
| [roles/release-master.md](roles/release-master.md) | Checking a finished card again and merging after the owner's yes | Release master |
| [roles/developer.md](roles/developer.md) | Logic, data and services | Developer |
| [roles/designer.md](roles/designer.md) | How the SwiftUI views look | Designer |
| [roles/tester.md](roles/tester.md) | Checking the card in the running Dev build, and all tests | Tester |
| [roles/reviewer.md](roles/reviewer.md) | Reading code and tests, privacy and safety first | Reviewer |
| [roles/documenter.md](roles/documenter.md) | Keeping `docs/` in step | Documenter |
| [../docs/process/agent-flow.md](../docs/process/agent-flow.md) | The flow, the statuses and the definition of done | everyone |
| [../docs/process/safety-and-privacy.md](../docs/process/safety-and-privacy.md) | The maintainer's Mac, the public repository, the app's own rules | everyone. The Reviewer reads it in full for every task |
| [../docs/process/releases.md](../docs/process/releases.md) | Versions and the Dev and Release builds. Its "Rules for agents" are binding | everyone |
| [../docs/process/checks.md](../docs/process/checks.md) | `./scripts/check`, the hooks and the `local/check` receipt | everyone who commits |

## The result line

Every role the Leader calls ends its final message with exactly one line:

```
RESULT: <DONE | NEEDS_DESIGN | NEEDS_DECISION | PASS | FAIL | APPROVE | REJECTED> – <one sentence>
```

The Leader reads this line first, then checks every claim in the report before it moves the card.

## Verdicts

The Tester and the Reviewer post their verdict as a comment on the pull request, because all agents share one GitHub account and cannot approve. The first line names the commit it was given on:

```
APPROVE: <short reason> (on <short sha>)
REJECTED: <short reason> (on <short sha>)
- <finding with file:line, severity and the fix>
```

A verdict belongs to that commit. A later commit that changes product code, tests, `rules/`, `.claude/` or `CLAUDE.md` needs a new verdict.

## Comments on the card

Only the Leader and the Release master touch the Trello board. Every step ends with a comment on the card, in this form:

```
**<Role>**: <what was done> → <what happens next>
```

Subagents report to the Leader, and the Leader posts the comment for their step under the role's name. Be concrete: files, pull request numbers, numbers from the check. Never a secret, never personal data. Paths in card comments, verdicts and pull requests are relative to the repository root, never absolute.

## Where the work happens

- Each card gets its own branch, `<type>/<card number>-<short-slug>` such as `feat/10-timer-engine`, and its own git worktree at `.worktrees/<branch>`, made from a fresh `origin/main`. All roles work in that worktree. The main checkout, where the session started, stays as it is.
- The rules are read from the main checkout: this `rules/` folder in the directory the session started in.
- Build, run and test only the Dev variant. See `docs/process/releases.md`.
- Never pass `--no-verify`, never force-push, never rewrite pushed history.

## Who changes this folder

Only the Leader, and only after the owner's yes. That covers `rules/`, `.claude/agents/` and `.claude/skills/`. Every other role says what should change in its report to the Leader.

## Language

Everything is written in English: code, comments, commits, pull requests, docs and Trello comments.
