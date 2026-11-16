# Lessons

What went wrong, and the rule that came from it. The Leader reads this file at the start of every card.

## When an entry is written

The Leader writes one after a bad outcome: two or more failed rounds, a decision the owner corrected, a blocked merge, or a cancelled task.

An entry never goes onto the card's own branch, because a change to `rules/` there would need new verdicts, and a cancelled card's branch never merges. The Leader shows the entry to the owner in the chat and in a comment on the card. It is then committed in a pull request of its own, on a branch `docs/lesson-<short-slug>`, together with the rule change when the owner accepted it.

## The entry format

```
## <date> · <short title> · <status>

- **What happened:** <facts, with the card and the pull request>
- **Root cause:** <why, not who>
- **Proposed change:** <the rule, and the file it goes into>
```

## The three statuses

| Status | Meaning |
|---|---|
| `proposed` | Written by the Leader and waiting for the owner, in the chat or in an open pull request. Not binding yet |
| `accepted` | The owner said yes. The rule is written into the file named, through a pull request, and is binding |
| `declined` | The owner said no. The entry stays, with his reason, so it is not proposed again |

Nothing in a rule or an agent changes without the owner's yes.

## Carried over from the reference flow

These were learned in the reference flow before this project started. All are `accepted`, and each is already written where the table says.

| Rule | Written in |
|---|---|
| Stop only the processes you started, by the process ID you recorded. Never a name pattern | `safety-and-privacy.md`, `testing.md`, `roles/developer.md`, `roles/designer.md`, `roles/tester.md` |
| Anything that deletes or rewrites data runs against a throwaway store | `testing.md`, `safety-and-privacy.md` |
| A pull request that conflicts only because another merged first gets `main` merged in with a normal merge commit. No rebase, no force-push. Not a failed round | `git.md`, `roles/release-master.md`, `roles/leader.md` |
| A blocked task whose session has stopped can be taken over by any Leader, in its own worktree | `roles/leader.md` |
| Before work starts, list the open pull requests and the files they change | `roles/leader.md` |
| A skipped test is not a pass. Tests run with the check command's settings | `testing.md`, `definition-of-done.md` |
| A card that touches a shared element lists that element's documented limits | `roles/leader.md` |
| A new dependency is named on the card with its license and the reason, and the Reviewer checks both | `roles/leader.md`, `roles/reviewer.md`, `safety-and-privacy.md` |
| Light and dark are each checked on a fresh launch with the mode already set | `testing.md`, `roles/designer.md` |
| A look the design docs do not show needs the owner's reference first, and the proposal is shown as a whole screen | `roles/leader.md`, `roles/designer.md` |
| A screen test performs at least one real interaction | `testing.md` |
| Every new way into the app from outside limits the size and checks the shape of what it reads | `safety-and-privacy.md`, `roles/reviewer.md` |

## Entries

None yet.
