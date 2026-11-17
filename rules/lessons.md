# Lessons

What went wrong, and the rule that came from it. The Leader reads this file at the start of every card.

## When an entry is written

The Leader writes one after a bad outcome: two or more failed rounds, a decision the owner corrected, a blocked merge, or a cancelled task.

An entry never goes onto the card's own branch, because a change to `rules/` there would need new verdicts, and a cancelled card's branch never merges. The Leader shows the entry to the owner in the chat and in a comment on the card. It is then committed in a pull request of its own, together with the rule change when the owner accepted it. That is a task like any other: a card of its own when there is a board, and a branch named as `rules/git.md` says.

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

## 2026-11-17 · Typing into a terminal by script · accepted

- **What happened:** on card #5 (PR #8), an agent sent `/exit` into a Terminal tab with `do script`, which sends the text and Return at once. Claude Code completed it to a different slash command, which offered to change a real profile's settings. The agent cancelled it. Later, Terminal and iTerm2 stopped answering Apple events (error −1712) while a dialog was open on screen.
- **Root cause:** no rule said how an agent types into a terminal by script, or what an Apple event timeout means.
- **Proposed change:** two rules in `safety-and-privacy.md`, "Permissions and the system".

## 2026-11-17 · A profile's settings file can be shared · accepted

- **What happened:** on card #5 (PR #8), the owner approved changing one profile's `settings.json`. It was a symlink to another profile's file, which every profile on the Mac shares. The spike's precheck stopped, and the owner then approved the shared file itself.
- **Root cause:** the rules treat each profile's settings file as its own.
- **Proposed change:** one rule in `safety-and-privacy.md`, "Claude Code profiles and other tools".

## 2026-11-17 · Removing a temporary folder · accepted

- **What happened:** on card #5 (PR #8), Claude Code's safety check refused an agent's `rm -rf "$WORK"`, and nothing ran. The folder was then removed by its literal path.
- **Root cause:** no rule said how an agent removes the temporary folders the rules ask for.
- **Proposed change:** one rule in `safety-and-privacy.md`, "Builds and data", which every role reads.
