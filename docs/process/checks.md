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

One command, `./scripts/check`, runs everything in this order and stops at the first failure:

1. SwiftFormat in lint mode, with the rules in `.swiftformat`
2. SwiftLint, strict, with the rules in `.swiftlint.yml`
3. `xcodegen generate`
4. Build of the Mac app and the hook tool in Swift 6 mode, with warnings treated as errors
5. Unit tests of `DontBurnCore`, with code coverage
6. The privacy scan, described below

It ends with one summary line:

```
check: PASS | format 0s · lint 0s · generate 0s · build 3s · tests 5s · privacy 0s | coverage 100% | total 8s
check: FAIL at tests | format 0s · lint 0s · generate 0s · build 2s · tests failed
```

The coverage is the share of lines in `DontBurnCore`'s sources that the tests run. The target is 80%. It is printed but does not fail the check yet.

`./scripts/bootstrap` prepares a fresh clone. It points git at the hooks in `.githooks/`, names the tools that are missing, and says whether a private word list is set.

### The string catalog

A build in the Xcode app rewrites `Apps/Mac/Localizable.xcstrings`: it adds the strings the code uses and deletes the keys it believes are unused. A build with `xcodebuild` never rewrites the catalog, so the check cannot see this kind of drift.

The app target sets `SWIFT_EMIT_LOC_STRINGS: YES` in `project.yml`, so the compiler reports every interface string the code uses and the Xcode app has no reason to delete a key. After a build in the Xcode app, look at `git status` before committing, and say so on the card if the catalog changed without a change to the interface text.

### The privacy scan

It reads every file git tracks, plus new files that are not ignored, and fails on any of these:

- a pattern from the private word list. It prints only the file and the line, never the word
- an email address, except GitHub's noreply addresses and `git@github.com`
- an absolute home path such as `/Users/<name>/`
- a commit on the branch, after `origin/main`, whose author or committer address is not a GitHub noreply address

The private word list is a file outside the repository, with one extended regular expression per line. The check finds it through the `DONTBURN_PRIVACY_WORDS` environment variable, or else through `git config dontburn.privacyWords <path>`. That setting lives in the clone's own `.git/config` and is never committed. Without a list, the word check is skipped and says so. The other three checks always run.

## The receipt

When the check passes on a clean working tree, it is proof about one commit. That proof is posted to GitHub as a commit status with the context `local/check`, and the pull request shows it next to the commit.

How it works:

1. `./scripts/check` passes on a clean working tree and records the pass in `.git/local-check/<sha>`. Worktrees share this folder, because it sits in the repository's common git folder.
2. `scripts/receipt <commit>` posts the status for a recorded commit, once GitHub has that commit. The check calls it at the end, so a check on a commit that is already pushed posts at once.
3. `./scripts/push` runs `git push` and then `scripts/receipt` for the pushed commit. A plain `git push` still runs the check through the hook but posts nothing, until `scripts/receipt` is run for that commit.

How agents push is in [../../rules/git.md](../../rules/git.md) under "Pushing".

What follows from this:

- A dirty working tree gets no receipt, because the pass would not describe the commit.
- GitHub accepts a status only for a commit it already has. That is why the hook only records the pass, and the status is posted after the push.
- A commit made after the check has no status until it is checked again.
- Anyone who can push can also post a status. The receipt is a record, not a lock. That is why the Tester and the Release master run the check again themselves.
- Without `gh`, or when it is not signed in, the pass is recorded and nothing is posted. The check still passes.

Reading the receipt:

```sh
gh api repos/{owner}/{repo}/commits/<sha>/status --jq '.statuses[] | select(.context=="local/check") | .state'
```

It prints `success` for a commit that passed, and nothing for a commit nobody checked.

## Git hooks

| Hook | What it does |
|---|---|
| `pre-commit` | SwiftFormat and SwiftLint on the staged Swift files. Fast |
| `commit-msg` | Conventional Commits: `feat:`, `fix:`, `test:`, `docs:`, `refactor:`, `chore:`, with an optional scope such as `fix(hook):`. Merge, revert, `fixup!` and `squash!` subjects pass |
| `pre-push` | The whole check command. A failure stops the push |

The pre-push hook refuses two things the check could not vouch for: a dirty working tree, and a push of a commit that is not the one checked out. A tag, annotated or lightweight, counts as the commit it points to, so a tag on the checked-out commit can be pushed with `git push origin <tag>`. A tag on any other commit is refused. A commit that already passed is not checked twice. A push that only deletes branches sends no commit, so it goes through without either guard or the check.

`git commit --no-verify` and `git push --no-verify` would skip these hooks. The rule about that, and what happens when a hook is wrong, are in [../../rules/git.md](../../rules/git.md) under "Commits".

## What GitHub enforces

The repository is public, so rulesets are available on the free plan. A ruleset named `main` protects the default branch:

- changes arrive only through a pull request. No approval is required, because the agents and the maintainer share one GitHub account, and an account cannot approve its own pull request
- the head commit must carry a successful `local/check` status. A pull request without it shows as blocked
- no force-push to `main`, and `main` cannot be deleted

Repository admins can bypass it. That is the maintainer's account, which the agents also use, so GitHub does not stop them. The bypass is closed by a rule instead, in [../../rules/git.md](../../rules/git.md) under "Never".

The flow checks it too: the Release master reads the status and runs the check again before asking for the owner's yes.

Pull requests from other people cannot get the `local/check` status from their own Mac. Until a workflow exists, the maintainer checks such a pull request out with `gh pr checkout <number>`, runs `./scripts/check`, and the check posts the receipt on its head commit, because GitHub already has it. A workflow on GitHub's own runners, free for public repositories, can take this over later.

## A runner of your own

Possible, and not used. A self-hosted runner would start workflows on the developer's Mac by itself. The check command with its receipt gives the same proof with nothing running in the background.

This repository is public, so a self-hosted runner is out: a stranger's pull request could run code on that Mac. If the repository ever turns private and one is set up, these rules apply: no job starts by itself for code nobody has read, actions are pinned by commit, secrets are removed after every run, and clean-up commands name fixed resources and never prune daemon-wide.
