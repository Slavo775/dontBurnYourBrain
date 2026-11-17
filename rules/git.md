# Git, pull requests and verdicts

## Branch and worktree

- One card, one branch, one pull request.
- The branch is `<type>/<card number>-<short-slug>`, such as `feat/10-timer-engine`. The type is one of the commit types below. Without a board there is no number: `<type>/<short-slug>`.
- **Every task starts from a fresh `main`:** `git fetch origin`, then `git worktree add .worktrees/<branch> -b <branch> origin/main`. Run every command inside that worktree. The main checkout stays as it is.
- A dirty working tree at the start of a task means stop and ask. Never stash, reset or discard someone else's changes.
- Never check out or remove another session's worktree.

## Commits

- Conventional Commits, checked by the `commit-msg` hook: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`, with an optional scope such as `fix(hook):`.
- Every commit carries GitHub's noreply address. Nothing personal in a message. See [safety-and-privacy.md](safety-and-privacy.md).
- The hooks run SwiftFormat and SwiftLint before a commit and the whole check before a push. **Never pass `--no-verify`.** If a hook is wrong, say so. It is fixed in its own pull request.

## Pushing

- Run `./scripts/check` in the worktree first.
- **Push with `./scripts/push`.** It pushes and then posts the `local/check` receipt for that commit. A plain `git push` posts nothing, so run `scripts/receipt <commit>` after it.
- **The push form.** The first push of a new branch is `./scripts/push -u origin <branch>`, and every later push is `./scripts/push`. In a takeover worktree, where the local branch is `takeover/<branch>` (`rules/roles/leader.md` section 7), every push is `./scripts/push origin HEAD:<branch>`. There, the plain form fails because the names differ, and `<branch>` alone pushes the stopped session's local branch instead, which leaves the new commits behind, sometimes with exit 0.
- A commit made after the check has no receipt until it is checked again.

## The pull request

- Opened with `gh pr create`. The title is a Conventional Commit. The body has the card's link, what changed, and how it was checked.
- Docs go into the same pull request.
- Nobody merges but the Release master, after the owner's yes.

## Verdicts

The Tester and the Reviewer post their verdict as a comment on the pull request, because all agents share one GitHub account and cannot approve. The first line names the commit it was given on:

```
APPROVE: <short reason> (on <short sha>)
REJECTED: <short reason> (on <short sha>)
- <finding with file:line, severity and the fix>
```

A verdict belongs to that commit. It still counts for a later head commit only when both of these hold:

- Every commit made on the branch since then changes only `docs/` or the root `README.md`. A change to product code, tests or a gated path (see "Who changes the rules" in [README.md](README.md)) needs a new verdict.
- Every merge since then was a clean merge of `main`: nobody resolved a conflict by hand. A merge with a conflict, or a merge of anything but `main`, needs a new verdict.

## When a pull request stops being mergeable

When the only reason is that another pull request merged first, the role that owns the conflicting files merges `main` into the branch with a normal merge commit. Never a rebase, never a force-push. The check runs again. Whether the verdicts still count is said under "Verdicts" above. This is a merge step, not a failed round.

## Never

- Never force-push, and never rewrite pushed history.
- Never bypass the ruleset on `main`, even though the shared account could.
- Never create or move a tag. See [releases.md](releases.md).
