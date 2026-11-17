# Definition of done

Two checklists. The Leader goes through the first before a card moves to Ready to merge. The Release master goes through the second before asking the owner for the yes. Every item needs evidence from this session: a command's output, a comment, a file. A claim in a report is not evidence.

## 1. Before Ready to merge (Leader)

- [ ] Every item of the card's done-when list is met, and you can point at the evidence for each.
- [ ] `./scripts/check` passed on the head commit of the pull request, and that commit carries the `local/check` status as `success`.
- [ ] The Tester posted `APPROVE:` on the pull request. A card that changes what the app does was checked in the running Dev build, including the case where an optional part is missing, and tests were added or updated. A card that changes nothing in the app, or a spike, was checked the way its "How to verify" says. When a screen changed, there are screenshots in light and dark, and the owner has seen them.
- [ ] The Reviewer posted `APPROVE:`, with no open CRITICAL or HIGH finding.
- [ ] Both verdicts still count for the head commit, as "Verdicts" in `rules/git.md` says.
- [ ] No test is skipped, or each skipped test is named on the card with its reason and the owner accepted it.
- [ ] Docs are updated in the same pull request, or the Documenter said why none are needed.
- [ ] The privacy scan is clean: nothing personal in code, docs, screenshots, commit messages or the pull request.
- [ ] No more than three failed rounds. Otherwise the card went to Needs decision and the owner decided.
- [ ] The card has a comment for every step, links the pull request, and its checklist is ticked.

## 2. Before the merge (Release master)

- [ ] The card is in Ready to merge.
- [ ] The head commit of the pull request carries `local/check` as `success`.
- [ ] You ran `./scripts/check` yourself, in the card's worktree, on a clean tree whose `HEAD` is the head commit, and it passed.
- [ ] A Tester `APPROVE:` and a Reviewer `APPROVE:` are on the pull request, with no later `REJECTED:`, and both still count for the head commit.
- [ ] The Documenter's note is on the card: what was documented, or why nothing was needed.
- [ ] The pull request's `mergeStateStatus` is `CLEAN`.
- [ ] The card has a comment for every step.
- [ ] The owner said yes to this pull request, in this session, after seeing every changed file under the gated paths of `rules/README.md` named.

When an item of the second list fails, the card goes to Merge blocked with a comment that says which one. The Release master fixes nothing.
