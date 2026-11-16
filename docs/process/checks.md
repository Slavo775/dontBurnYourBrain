# Checks

Decided: lint, build and tests run on the developer's Mac, and GitHub runs only releases.

The decision was made for cost: on a private repository, tests on GitHub's Mac runners use up the free minutes ten times faster than Linux jobs do. The repository is public now, and GitHub's own runners are free for public repositories, so cost no longer forces it. Checks stay local anyway, because the local run is faster and the receipt already proves which commit passed. A workflow can be added later without changing anything else.

## What runs where

| What | Where | When |
|---|---|---|
| Lint, format, build and unit tests | Locally, one check command | Before every push, through a git hook, and again by the Tester and the Release master |
| Proof on the pull request | A commit status that the check command posts when it passes | For the exact commit it ran on. A later commit has none until it is checked |
| Screen tests | Locally, run by the Tester | Tasks that change a screen |
| Release: build, sign, notarize, publish | GitHub Actions, started by a version tag | From phase 8, a few runs a month |
| Checks on pull requests from other people | The maintainer runs the check locally on the branch, or later a workflow on GitHub's own runners | When the first one arrives |

## The check command

Card 1 builds it. One command, `./scripts/check`, runs everything in this order and stops at the first failure:

1. SwiftFormat in lint mode
2. SwiftLint, strict
3. `xcodegen generate`
4. Build of the Mac app in Swift 6 mode, with warnings treated as errors
5. Unit tests of `DontBurnCore`
6. The privacy scan, on machines where the private word list exists
7. One summary line with the result and the time each step took

`./scripts/bootstrap` prepares a fresh clone: it points git at the hooks in `.githooks/`.

## The receipt

When the check passes on a clean working tree, it is proof about one commit. That proof is posted to GitHub as a commit status with the context `local/check`, and the pull request shows it next to the commit.

- A dirty working tree gets no receipt, because the pass would not describe the commit.
- GitHub accepts a status only for a commit it already has. So the hook records the pass locally before the push, and the status is posted right after the push.
- A commit made after the check has no status until it is checked again.
- Anyone who can push can also post a status. The receipt is a record, not a lock. That is why the Tester and the Release master run the check again themselves.

Reading the receipt:

```sh
gh api repos/{owner}/{repo}/commits/<sha>/status --jq '.statuses[] | select(.context=="local/check") | .state'
```

## Git hooks

| Hook | What it does |
|---|---|
| `pre-commit` | SwiftFormat and SwiftLint on the staged Swift files. Fast |
| `commit-msg` | Conventional Commits: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:` |
| `pre-push` | The whole check command. A failure stops the push |

Never pass `--no-verify`. If a hook is wrong, fix the hook in its own pull request.

## What GitHub enforces

The repository is public, so rulesets are available on the free plan. Card 1 adds one to `main`: changes arrive only through a pull request, and the head commit must carry a successful `local/check` status. The maintainer can bypass it, for example for the first commits of the project.

The flow checks it too: the Release master reads the status and runs the check again before asking for the owner's yes.

Pull requests from other people cannot get the `local/check` status from their own Mac. Until a workflow exists, the maintainer runs the check on such a branch himself.

## A runner of your own

Possible, and not used. A self-hosted runner would start workflows on the developer's Mac by itself. The check command with its receipt gives the same proof with nothing running in the background.

This repository is public, so a self-hosted runner is out: a stranger's pull request could run code on that Mac. If the repository ever turns private and one is set up, these rules apply: no job starts by itself for code nobody has read, actions are pinned by commit, secrets are removed after every run, and clean-up commands name fixed resources and never prune daemon-wide.
